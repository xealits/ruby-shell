#!/usr/bin/ruby

pid = ARGV[0]
p "reading stdout of #{pid}"
open("/proc/#{pid}/fd/1", 'r') { |output_file|
    while s = output_file.gets
      puts s
    end
}
