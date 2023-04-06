#!/usr/bin/ruby

pid = ARGV[0]
p "writing to stdin of #{pid}"
open("/proc/#{pid}/fd/0", 'w') { |input_fd|
  while s = STDIN.gets
    input_fd.write_nonblock s
  end
}
