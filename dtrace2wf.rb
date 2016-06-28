#!/usr/bin/env ruby

require 'pathname'
require 'socket'

CHUNKS_PER_SEND  = 1
POLL_INTERVAL    = 0.1
HOSTNAME         = Socket.gethostname
METRICS_ENDPOINT = 'wavefront.localnet'
METRICS_PORT     = 2878
LINE_FORMAT      = %r{^(\d+)\s+(\d+)$}

#-----------------------------------------------------------------------
# METHODS

def flush_metrics(data, prefix)
  timestamp = Time.now.to_i

  begin
    sock = TCPSocket.open(METRICS_ENDPOINT, METRICS_PORT)
  rescue
    abort "ERROR: cannot open socket to #{METRICS_ENDPOINT}."
  end

  begin
    data.each do |bucket, value|
      sock.puts "#{prefix}.#{bucket} #{value} #{timestamp} source=#{HOSTNAME}"
    end
  rescue
    puts 'WARNING: could not sent metrics.'
  end

  sock.close
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
prefix = ARGV.first
FIFO = Pathname.new('/tmp') + prefix

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
          flush_metrics(process_buffer(buffer), prefix)
          buffer = []
        end

      end
    end
  end

  sleep POLL_INTERVAL
end
