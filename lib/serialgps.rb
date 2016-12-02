#
# Provides an easy way to get GPS data from your serial GPS unit.
#
# == Data
# Currently only $GPGGA and $GPRMC NMEA sentences are parsed -- but these have the most
# useful information anyways. For more information on NMEA sentences: http://aprs.gids.nl/nmea/
#
# == Requirements
# * A serial GPS module. (This was tested with the EM-406A SiRF III GPS receiver)
# * serialport ruby gem (http://rubyforge.org/projects/ruby-serialport/)
#
# == Install
# <code>$ gem install ruby-serialport </code>
#
# Author:: Jeremy Gillick (http://blog.mozmonkey.com/)
# License:: Distributes under the same terms as Ruby
#

require 'rubygems'
require 'serialport'
require 'date'
require 'vincenty'


# Connects to the GPS unit and parses the NMEA sentences.
class SerialGPS
	#
	# last_nmea::  				The last NMEA sentence name (without "$GP") parsed with the read method.
	# quality::					0 = invalid, 1 = GPS fix, 2 = DGPS fix
	# validity::				A = ok, V = invalid
	# latitude::				Latitude
	# lat_ref::					North/South (N/S)
	# longitude::				Longitude
	# long_ref::				East/West (E/W)
	# Repeated in
	#   rma_validity::				A = ok, V = invalid
  #   rma_latitude::				Latitude
	#   rma_lat_ref::					North/South (N/S)
	#   rma_longitude::				Longitude
	#   rma_long_ref::				East/West (E/W)
  #   gll_validity::				A = ok, V = invalid
	#   gll_time::					Current time formated as HHMMSS.SS -- use date_time to get the parsed version
	#   gll_latitude::				Latitude
	#   gll_lat_ref::					North/South (N/S)
	#   gll_longitude::				Longitude
	#   gll_long_ref::				East/West (E/W)
	#   rmc_time::					Current time formated as HHMMSS.SS -- use date_time to get the parsed version
	#   rmc_validity::				A = ok, V = invalid
	#   rmc_latitude::				Latitude
	#   rmc_lat_ref::					North/South (N/S)
	#   rmc_longitude::				Longitude
	#   rmc_long_ref::				East/West (E/W)
	# altitude::				Current altitude
	# alt_unit::				Altitude height unit of measure (i.e. M = Meters)
	# speed::					Speed over ground in knots
	# heading::					Heading, in degrees
	# course::					Course over ground in degrees
	# time::					Current time formated as HHMMSS.SS -- use date_time to get the parsed version
	# date::					Current date formated as DDMMYY -- use date_time to get the parsed version
	# local_hour_offset::		Local zone description, 00 to +/- 13 hours
	# local_minute_offset::		Local zone minutes description (same sign as hours)
	# num_sat::					The number of satellites in view
	# active_satellites::			An array holding id's of upto 12 active satellites (use as keys to visible_satellites)
	# visible_satellites::	A hash, indexed by id, elevation, azimuth and SNR for each satellite
	# height_geoid::			Height of geoid above WGS84 ellipsoid
	# height_geoid_unit::		Unit of measure (i.e. M = Meters)
	# last_dgps::				Time since last DGPS update
	# dgps::					DGPS reference station id
	# mode::					M = Manual (forced to operate in 2D or 3D) A = Automatic (3D/2D)
	# mode_dimension::			1 = Fix not available, 2 = 2D, 3 = 3D
	# hdop::					Horizontal Dilution of Precision
	# pdop::					Positional Dilution of Precision
	# vdop::					Vertical Dilution of Precision
	# msg_count::				Total number of messages of this type in this cycle
	# msg_num::					Message number
	# variation::				Magnetic variation
	# var_direction::			Magnetic variation direction (i.e E = East)
	#
	attr_reader :data

	# Connect to the serial device.
	def initialize(device, baud=4800, bits=8, stop=1, parity=SerialPort::NONE)
		#Set up serial port
		@serial = SerialPort.new(device, baud, bits, stop, parity)
		@serial.flow_control = SerialPort::NONE
		#@serial.binmode
		@serial.rts = 1
		@serial.dtr = 1
		@serial.read_timeout = 30 * 1000 # 10 second timeout for reads

		#Initialize the @data hash, as outlined above
		@data = {}
		@data[:latitude] = 0
		@data[:longitude] = 0

	end

	# Close the serial connection to the GPS unit.
	def close
		@serial.close
	end


	# Parses the next NMEA sentence from the GPS and returns the current GPS data hash.
	def read

		# Parse NMEA sentence until we find one we can use
		while true do
			nmea = next_sentence
			data = parse_NMEA(nmea)

			# Sentence parsed, now merge
			unless data[:last_nmea].nil?
				@data.merge!(data) do |k, v_old, v_new|
					if k == :visible_satellites
						v_old.merge!(v_new)
						v_old
					else
						v_new
					end
				end
				break
			end

		end

		return @data
	end

	# Retuns the next raw NMEA sentence string
	def next_sentence

		# Loop through serial data
		buffer = ""
		checksum = 0
		checksum_str = ""
		in_checksum_str = false
		while true do
			c = @serial.getc
			if c.nil?
				raise "Can't connection to the GPS!"
			end

			# End of the line, collect the data
			if c == "\n"
				buffer.lstrip!

				# Valid sentence
				if buffer[0,1] == "$" && ("%02X"%checksum == checksum_str.strip)
					break

				# Try again, probably a partial line
				else
					checksum = 0
					checksum_str = ""
					in_checksum_str = false
					buffer = ""
				end

			elsif c == '*' #Start of checksum
		       in_checksum_str = true
			# Add to buffer
		    elsif in_checksum_str
				checksum_str << c
			else
				checksum ^= c.ord if c != '$'
				buffer << c
			end
		end

		buffer
	end

	#Given the antenna's known coordinates, return the track and distance
	#to the last GPS coordinates.
	# @param antenna [Vincenty]
	def actual_error(antenna)
		return 0 if @data[:latitude] == nil || @data[:longitude] == nil
		begin
			latitude = @data[:latitude] * (@data[:lat_ref] == 'N' ? 1:-1)
			longitude = @data[:longitude] * (@data[:long_ref] == 'E' ? 1:-1)
			gps_location = Vincenty.new(latitude, longitude)
			antenna.distanceAndAngle(gps_location)
		rescue Exception => error
			puts "Actual_error(): #{error}"
			return 0
		end
	end

	# Continuous updated output of the live GPS data to the console.
	# If the antenna location is given, also output the track and distance
	# to from the known location to the GPS location
	# @param known_antenna_location [Vincenty]
	def live_gps_dump(known_antenna_location = nil)
		puts "Reading...\n"
		data = {}
		rows = 1
		errors = 0

		while true do
			begin
				read
#=begin
				# Clear previous data
				if rows > 0
					$stdout.print "\e[#{rows}A\e[E\e[J"
					rows = 0
				end
#=end
				errors = 0

				# Get date
				date = self.date_time
				unless date.nil?
					date = date.strftime("%Y-%m-%d %H:%M:%S")
				end

				num_sat = @data[:num_sat] || 0
				$stdout.print "UTC: #{date}   Active Satellites: #{num_sat} of #{@data[:num_sat_in_view]}   #{@data[:mode_dimension]}D\n"
				$stdout.print "Latitude: #{@data[:latitude] * (@data[:lat_ref] == 'N' ? 1:-1)}"
				$stdout.print "\tLongitude: #{@data[:longitude] * (@data[:long_ref] == 'E' ? 1:-1)}"
				$stdout.print " +/-#{@data[:horizontal_error]}#{@data[:horizontal_error_units]}\n"
				if known_antenna_location != nil
					$stdout.print "Actual error: #{actual_error(known_antenna_location)}\n"
					rows += 1
				end
=begin
				$stdout.print "Latitude: #{@data[:rmc_latitude]}#{@data[:rmc_lat_ref]}"
				$stdout.print "\tLongitude: #{@data[:rmc_longitude]}#{@data[:rmc_long_ref]} RMC: #{@data[:rmc_time]}\n"
				$stdout.print "Latitude: #{@data[:gll_latitude]}#{@data[:gll_lat_ref]}"
				$stdout.print "\tLongitude: #{@data[:gll_longitude]}#{@data[:gll_long_ref]} GLL: #{@data[:gll_time]}\n"
=end
				$stdout.print "Elevation: #{@data[:altitude]}#{@data[:alt_unit]}"
				$stdout.print " +/-#{@data[:altitude_error]}#{@data[:altitude_error_units]}"
				$stdout.print "\tSperical Error: #{@data[:sperical_error]}#{@data[:sperical_error_units]}\n"
				$stdout.print "Coordinate System: #{@data[:coordinate_system]}\n"
#				$stdout.print "HDOP #{@data[:hdop]}   VDOP #{@data[:vdop]} PDOP #{@data[:pdop]}\n"
				rows += 5

				# Satellites
				if @data.key?(:num_sat_in_view)
					$stdout.print "-- Satellites --\n"


					(0...12).each do |i|
						if @data[:active_satellites] != nil &&
						   (id = @data[:active_satellites][i]) != nil
							sat = @data[:visible_satellites][id]
							if sat != nil
								rows += 1

								$stdout.print "#{"%2d"%(i+1)} #{"%3s"%id}:"
								$stdout.print " #{sat[:last_seen].strftime("%H:%M:%S")}"
								$stdout.print "   Elevation: #{"%3s"%sat[:elevation]}"
								$stdout.print "   Azimuth: #{"%3s"%sat[:azimuth]}"
								$stdout.print "   SNR: #{"%3d"%sat[:snr]}\n"
						    end
						end
					end
					rows += 1
				end

			rescue Exception => e
				# Clear previous error
				if errors > 0
					$stdout.print "\e[1A\e[E\e[J"
					errors = 0
				end

				$stdout.print "\nERROR: #{e.message}\n"
				break
			end

			$stdout.flush
		end
	end

	# Returns a DateTime object representing the date and time provided by the GPS unit or NIL if this data is not available yet.
  # @return [DateTime] as obtained from the GPS
	def date_time()
		@data.inspect
		if !@data.key?(:time) || @data[:time].empty? || !@data.key?(:date) || @data[:date].empty?
			return nil
		end

		time = @data[:time]
		date = @data[:date]
		time.gsub!(/\.[0-9]*$/, "") # remove decimals
		datetime = "#{date} #{time} UTC"

		date =  DateTime.strptime(datetime, "%d%m%y %H%M%S %Z")
		date
	end

	# Convert a Lat or Long NMEA coordinate to decimal
	def latLngToDecimal(coord)
		coord = coord.to_s
		decimal = nil
		negative = (coord.to_i < 0)

		# Find parts
		if coord =~ /^-?([0-9]*?)([0-9]{2,2}\.[0-9]*)$/
			deg = $1.to_i # degrees
			min = $2.to_f # minutes & seconds

			# Calculate
			decimal = deg + (min / 60)
			if negative
				decimal *= -1
			end
		end

		decimal
	end

	# Parse a raw NMEA sentence and respond with the data in a hash
	def parse_NMEA(raw)
		data = { :last_nmea => nil } #Set up default as empty record, of type nil
		if raw.nil?
			return data
		end
		#raw.gsub!(/[\n\r]/, "")

		line = raw.split(",");
		if line.size < 1
			return data
		end

		# Invalid sentence, does not begin with '$'
		if line[0][0, 1] != "$"
			return data
		end

		# Parse sentence
		type = line[0][3, 3]
		line.shift

		if type.nil?
			return data
		end

		case type
			#$GPGGA,002909,3659.418,S,17429.240,E,1,06,1.5,165.3,M,28.0,M,,*5F
			when "GGA" # Global Positioning Fix
				data[:last_nmea] = type
				data[:time]				= line.shift                   #002909 HHMMSS UTC
				data[:latitude]			= latLngToDecimal(line.shift)  #3659.418 36Deg 59.418Minutes
				data[:lat_ref]			= line.shift                   #S South
				data[:longitude]		= latLngToDecimal(line.shift)  #17429.240 174deg 29.240min
				data[:long_ref]			= line.shift                   #E East
				data[:quality]			= line.shift                   #1 0=Invalid,1=GPS,2=DGPS
				data[:num_sat]			= line.shift.to_i              #6 Six satellites active
				data[:hdop]				= line.shift                   #1.5 Horizontal accuracy
				data[:altitude]			= line.shift                   #165.3 Altitude
				data[:alt_unit]			= line.shift                   #M Meters
				data[:height_geoid]		= line.shift                   #28.0 height of geoid above WGS84 ellipsod
				data[:height_geoid_unit] = line.shift                  #M meters
				data[:last_dgps]		= line.shift                   # Time since last DGPS update
				data[:dgps]				= line.shift                   # DGPS Reference station ID
				                                                       #*5F Checksum

			#$GPGLL,3659.418,S,17429.240,E,002910,A*36
			when "GLL" # Geographic position Latitude/Longitude
				data[:last_nmea] 	= type
				data[:gll_latitude]		= latLngToDecimal(line.shift) #3659.418 (36deg 59.418min)
				data[:gll_lat_ref]		= line.shift                  #S (South)
				data[:gll_longitude]	= latLngToDecimal(line.shift) #17429.240 (174deg 29.240min)
				data[:gll_long_ref]		= line.shift                  #E (East)
				data[:gll_time]			= line.shift                  #002910 (Time 00:29:10 UTC)
				data[:gll_validity]		= line.shift                #A A=OK, V=Warning
				                                                  #*36 Checksum

			#eg $GPRMA,A,llll.ll,N,lllll.ll,W,,,ss.s,ccc,vv.v,W*hh
			when "RMA" #Recommended Minimum Loran-C
				data[:last_nmea] = type
				data[:rma_validity]		= line.shift                #A A=OK, V=Warning
				data[:rma_latitude]		= latLngToDecimal(line.shift)  #Latitude
				data[:rma_lat_ref]		= line.shift                   #N/S
				data[:rma_longitude]	= latLngToDecimal(line.shift)  #Longitude
				data[:rma_long_ref]		= line.shift                   #E/W
				line.shift                                         # not used
				line.shift                                         # not used
				data[:rma_speed]			= line.shift               # Ground Speed Knots
				data[:rma_course]			= line.shift               # Course over Ground
				data[:rma_variation]	= line.shift                   # Variation
				data[:rma_var_direction]	= line.shift               # Direction of Variation E/W

			#$GPRMB,A,0.11,L,T001,B1,3659.509,S,17429.158,E,000.1,215.9,,V*1D
			when "RMB" # Recommended minimum navigation info
				data[:last_nmea] 	= type
				data[:rmb_validity]		= line.shift                     #A A=OK, V=Warning
        data[:rmb_cross_track_error] = line.shift              #0.11         Cross-track error (nautical miles, 9.9 max.),
        data[:rmb_steer_to]       = line.shift                 #L            steer Left to correct (or R = right)
        data[:rmb_origin]		      = line.shift                  #T001         Origin waypoint ID
        data[:rmb_destination]		= line.shift                  #B1           Destination waypoint ID
				data[:rmb_dest_latitude]	= latLngToDecimal(line.shift) #3659.509,S   Destination waypoint latitude 36 deg. 59.509 min
				data[:rmb_dest_lat_ref]		= line.shift                  #S (South)
				data[:rmb_dest_longitude]	= latLngToDecimal(line.shift) 	#17429.158,E  Destination waypoint longitude 174 deg. 29.158 min.
				data[:rmb_dest_long_ref]	= line.shift                  #E (East)
        data[:rmb_dest_distance]	= line.shift                  #000.1        Range to destination, nautical miles
        data[:rmb_dest_bearing]		= line.shift                  #215.9        True bearing to destination
        data[:rmb_speed]		      = line.shift                  #             Velocity towards destination, knots
        data[:rmb_arrived]		    = line.shift                  #V            Arrival alarm  A = arrived, V = not arrived
                                                                #*1D          mandatory checksum

			#$GPRMC,002909,A,3659.418,S,17429.240,E,000.0,360.0,201116,019.4,E*6E
			when "RMC" # Recommended Minimum specific GPS/Transit
				data[:last_nmea] = type
				data[:rmc_time]			= line.shift                  #002909 Time of Fix HHMMSS UTC
				data[:rmc_validity]		= line.shift                  #A A=OK, V=Warning
				data[:rmc_latitude]		= latLngToDecimal(line.shift) #3659.418 36Deg 59.418Minutes
				data[:rmc_lat_ref]		= line.shift                  #S (South)
				data[:rmc_longitude]	= latLngToDecimal(line.shift) #17429.240 174deg 29.240min
				data[:rmc_long_ref]		= line.shift                  #E (East)
				data[:rmc_speed]		= line.shift                  #000.0 Speed in Knots
				data[:rmc_course]		= line.shift                  #360.0 Course Made Good, True
				data[:rmc_date]			= line.shift                  #201116 Date 20th Nov 2016
				data[:rmc_variation]	= line.shift                  #019.4 Magnetic Variation 19.4deg
				data[:rmc_var_direction] = line.shift                 #E (East)
					                                                  #*6E Checksum

			#$PGRME,5.3,M,8.8,M,10.2,M*1B
			when "RME" #Estimated Position Error
				data[:last_nmea] 	= type
				#5.3,M  Estimated horizontal error in meters (HPE)
				data[:horizontal_error] = line.shift
				data[:horizontal_error_units] = line.shift
				#8.8,M  Estimated vertical error in meters (VPE)
				data[:altitude_error] = line.shift
				data[:altitude_error_units] = line.shift
				#10.2,M Overall Spherical equavalent postion error
				data[:sperical_error] = line.shift
				data[:sperical_error_units] = line.shift
				#*22    Checksum

			#$PGRMM,WGS 84*06
			when "RMM" #Map datum (Coordinate System)
				data[:last_nmea] 	= type
				data[:coordinate_system]	= line.shift  #WGS 84  Coordinate System
				                                        #*06 Checksum

			#$PGRMZ,543,f,3*19
			when "RMZ" # Altitude in feet, possibly pressure based
				data[:last_nmea] 	= type
				data[:rmz_altitude]			= line.shift        #573 Altitude
				data[:rmz_alt_unit]			= line.shift        #f Feet
				data[:rmz_mode_dimension] = line.shift      #3 1=Unknown,2=2D,3=3D
																										#*19   checksum


			#$GPGSA,A,3,,07,,09,11,,,,27,,30,,2.9,1.5,1.2*36
			when "GSA" #GPS DOP and active satellites
				data[:last_nmea] = type
				data[:mode]	= line.shift                           #A M=Manual,A=Automatic
				data[:mode_dimension] = line.shift                 #3 1=Unknown,2=2D,3=3D
				data[:active_satellites] = []

				# Satellite data
				(0...12).each do |i|
					id = line.shift                                #ID of Satellite, or null

					# No satallite ID, clear data for this index
					if id != nil && !id.empty?
					# Add satallite ID
					    data[:active_satellites][i] = id
					end
				end

				#These tell us how far apart the satellites are, hence our precision.
				data[:pdop]			= line.shift                  #Position Dilution of Precision
				data[:hdop]			= line.shift                  #Horizontal Dilution of Precision
				data[:vdop]			= line.shift                  #Vertical Dilution of Precision

			#$GPGSV 3 lines, to record up to 12 visible satellites signal and position
			#$GPGSV,3,1,11,01,13,040,00,07,78,148,38,08,61,114,30,09,39,342,41*79
			#$GPGSV,3,2,11,11,37,050,35,13,02,213,00,16,00,113,00,23,11,009,00*73
			#$GPGSV,3,3,11,27,23,137,36,28,30,273,32,30,50,223,45,,,,*47
			when "GSV"  #multiple: GPS Satellite view
				data[:last_nmea] 	= type
				data[:msg_count]	= line.shift                #3 Total number of messages of this type in this cycle
				data[:msg_num]		= line.shift.to_i  - 1      #1-3 Message number
				data[:num_sat_in_view]	= line.shift.to_i       #11 Satellites in view
				data[:visible_satellites] = {}

				# Satellite data
				(0..3).each do |i|
					id = line.shift  #Satellite number
					if id != nil && !id.empty?
					    data[:visible_satellites][id] = {}
						data[:visible_satellites][id][:elevation]	= line.shift  #Elevation in degrees (max 90)
						data[:visible_satellites][id][:azimuth]		= line.shift  #Azimuth, degrees from north
						data[:visible_satellites][id][:snr]			= line.shift  #Signal to noise ratio
						data[:visible_satellites][id][:last_seen] = Time.now.utc #Sanity check
					end
				end

			when "HDT" #Heading True
				data[:last_nmea] = type
				data[:heading]	= line.shift

			when "ZDA" #Date and Time
				data[:last_nmea] = type
				data[:time]	= line.shift

				day		= line.shift
				month	= line.shift
				year	= line.shift
				if year.size > 2
					year = [2, 2]
				end
				data[:date] = "#{day}#{month}#{year}"

				data[:local_hour_offset]		= line.shift
				data[:local_minute_offset]	= line.shift

			#$GPBOD,306.4,T,287.0,M,B1,T001*5D
			when "BOD" #Bearing, origin to destination
				data[:last_nmea] 	= type
				data[:bod_true] 	   = line.shift #306.4, T True bearing from origin to dest
				line.shift
				data[:bod_magnetic] = line.shift #287.0, M Magnetic bearing origin to dest
				line.shift
				data[:bod_destination_wp_id]	       = line.shift #B1       Destination waypoint ID
				data[:bod_origin_wp_id]	           = line.shift #T001     Origin waypoint ID
				#*5D      Checksum

			#$GPRTE,1,1,c,0,T002,T001,B1*5B
			when "RTE" #Routes
				data[:last_nmea] 	= type
				#1             Number of sentences in sequence
				#1             Sentence number
				#c             Current active route (if w, waypoint list starts with dest waypoint)
				#0             Name of active route
				#T002,T001,B1  Names of waypoints.
				#*5B           Checksum

			#$GPWPL,3659.640,S,17429.392,E,T002*3A
		when "WPL" #Waypoint Location
				data[:last_nmea] 	= type
				#3659.640,S  Latitude of waypoint
				#17429.392,E Longitude of waypoint
				#T002        Waypoint ID
				#*3A         Checksum

			#$PSLIB,,,J*22
			when "LIB" #Proprietry Garman Differential Control
				data[:last_nmea] 	= type
				#    Frequency
				#    Bit rate
				#J   Request Type (J=Status request, K=Configuration request, blank=Tuning)
				#*22 Checksum
		end

		# Remove empty data
		data.each_pair do |key, value|
			if value.nil? || (value.is_a?(String) && value.empty?)
				data.delete(key)
			end
		end

		data
	end
end
