#!/usr/bin/env ruby

# Copy of original Simple command line script that prints live GPS data to the console.
#
# == Usage
# From the command line, call the script with the GPS serial device as the only
# argument:
#
# <code>$ gpsdump.rb /dev/ttyUSB0</code>
#
# == Example Output
#
#   Time: Apr 20 11:44 AM 	Satellites: 05		Quality:1
#   Latitude: 4124.8963N	Longitude: 08151.6838W	Elevation: 35.7M
#

require "../lib/serialgps"

#Coordinates of the test antenna
LATITUDE = -36.990276129932404
LONGITUDE = 174.4873539718277
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

my_antenna = Vincenty.new(LATITUDE,LONGITUDE)
gps.live_gps_dump(my_antenna)
