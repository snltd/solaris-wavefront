#!/usr/bin/env ruby

#=======================================================================
#
# dtrace2wf.rb
# ------------
#
# Pull DTrace aggragated data out of a FIFO and turn it into basic
# Wavefront metrics. I chose to use a FIFO rather than STDIN as it
# gives a nice separation between privileged collector and
# unpriviliged aggretator/forwarder. The coupling can even be
# across zones with a correctly shared filesystems for the named
# pipe.
#
# As it stands, this script only understands simple two-column
# DTrace output, where the left column is an aggregation bucket
# whose name will become the final segment of the metric path, and
# the right column is the value which will be sent.
#
# Requires a readable FIFO. Create a fifo whose name is the first
# part of the metric path you desire, and direct your D script's
# output to it. For example:
#
#   $ mkfifo -m 666 /tmp/interrupts.cpu
#   $ ./cpu_latency.d >/tmp/interrupts.cpu
#
# then run this script with the path to the FIFO as the only
# argument.
#
# CAVEATS
# This is only really a proof-of-concept, illustrative program.  If
# this script dies, DTrace will exit. If this matters (!), put both
# under SMF control, with this service dependent on the D script.
#
# R Fisher 06/2016
#
#=======================================================================

require 'pathname'
require 'socket'

# If you want, you can bundle up metrics before sending them. This
# lets you do intervals which DTrace's tick() doesn't support.
#
CHUNKS_PER_SEND  = 1
POLL_INTERVAL    = 0.1
HOSTNAME         = Socket.gethostname
METRICS_ENDPOINT = 'wavefront.localnet'
METRICS_PORT     = 2878
LINE_FORMAT      = %r{^(\d+)\s+(\d+)$}

#-----------------------------------------------------------------------
# METHODS

def flush_metrics(data, prefix)
  #
  # Send data in Wavefront format over a socket.
  #
  timestamp = Time.now.to_i

  begin
    s = TCPSocket.open(METRICS_ENDPOINT, METRICS_PORT)
  rescue
    abort "ERROR: cannot open socket to #{METRICS_ENDPOINT}."
  end

  begin
    data.each do |bucket, value|
      s.puts "#{prefix}.#{bucket} #{value} #{timestamp} source=#{HOSTNAME}"
    end
  rescue
    puts 'WARNING: could not sent metrics.'
  end

  s.close
end

def process_buffer(buffer)
  #
  # What do you want to do here?  You could do all kind of StatsD
  # percentile/max/min stuff if you wished. I'll work out the
  # sums for every bucket over the interval. Turning those into a
  # mean would be trivial.
  #
  # Returns a hash of the form {bucket: sum}
  #
  buffer.each_with_object(Hash.new(0)) do |row, aggr|
    row.each { |bucket, count| aggr[bucket] += count.to_i }
  end
end

def process_raw_buf(raw_buf)
  #
  # Pulls together into one object all the separate lines of DTrace
  # output from a single tick. Ignores lines it can't understand.
  #
  # Returns an array of [bucket, count] arrays
  #
  raw_buf.each_with_object([]) do |line, aggr|
    begin
      aggr.<< line.match(LINE_FORMAT).captures
    rescue
      puts "WARNING: could not process #{line}"
    end
  end
end

#-----------------------------------------------------------------------
# SCRIPT STARTS HERE
#
abort 'Please supply a path to a FIFO' unless ARGV.size == 1

# The name of the fifo is the first part of the metric path
#
FIFO = Pathname.new(ARGV.first)

unless FIFO.exist? && FIFO.readable? && FIFO.pipe?
  abort "ERROR: can't read FIFO '#{FIFO}'."
end

buffer, raw_buf = [], []

# This loop uses two buffers. 'raw_buf' collects together all the
# lines of a DTrace aggregation. 'buffer' collects bucket->count
# pairs until it has enough to send to Graphite. Once you read a
# FIFO, it's empty, so it is safe to read faster than the D script
# writes.

loop do
  File.open(FIFO, 'r+') do |stream|
    loop do
      line = stream.gets

      if line.match(/^\s+\d+\s+\d+$/)
        raw_buf.<< line.strip
      elsif raw_buf.length > 0
        buffer.<< process_raw_buf(raw_buf)
        raw_buf = []

        if buffer.length == CHUNKS_PER_SEND
          flush_metrics(process_buffer(buffer), FIFO.basename)
          buffer = []
        end

      end
    end
  end

  sleep POLL_INTERVAL
end
