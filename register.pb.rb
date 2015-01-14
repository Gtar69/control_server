## Generated from atg/cloud/register.proto for atg.cloud
require "beefcake"


class ControlRegisterNodeRequest
  include Beefcake::Message
end

class ControlRegisterNodeResponse
  include Beefcake::Message
end

class ControlRegisterNodeRequest
  required :node, ControlNodeInstance, 1
  required :streamer, StreamerInstance, 2
  repeated :installed_packages, :string, 3
end

class ControlRegisterNodeResponse
  required :code, ControlMessage::Code, 1, :default => ControlMessage::Code::CODE_OKAY
  optional :message, :string, 2
end
