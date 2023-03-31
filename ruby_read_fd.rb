#!/usr/bin/ruby

pid = ARGV[0]
p "reading stdout of #{pid}"
open("/proc/#{pid}/fd/1", 'r') { |output_file|
    puts output_file.gets while true
}
