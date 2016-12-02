#!/usr/bin/env ruby

# Simple command line script that prints the raw output from the GPS
# Assumes output on GPS serial port is set to NMEA

require "../lib/serialgps"

DEFAULT_SERIAL_PORT = '/dev/ttyUSB0' #Linux USB to Serial adaptor

if ARGV.size > 1
	puts "USAGE gpsdump.rb <Serial Device>\n"
	puts "Example: gpsdump.rb /dev/ttyUSB0\n"
	exit 0
elsif ARGV.size == 1
  device = ARGV[1]
else
  device = DEFAULT_SERIAL_PORT
end
gps = SerialGPS.new(device)

puts "Control C to kill"
while true do
	puts gps.next_sentence
end
