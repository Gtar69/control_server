## Generated from atg/cloud/storage.proto for atg.cloud
require "beefcake"


class Storage
  include Beefcake::Message
end

class Storage
  required :host, :string, 1, :default => "127.0.0.1"
  required :port, :uint32, 2, :default => 0
  required :username, :string, 3, :default => "anonymous"
  required :password, :string, 4
  required :secure, :bool, 5, :default => true
  optional :connection_timeout, :uint32, 6, :default => 10
  optional :operation_timeout, :uint32, 7, :default => 15
end
