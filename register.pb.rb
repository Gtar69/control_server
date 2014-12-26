## Generated from atg/cloud/register.proto for atg.cloud
require "beefcake"


class ControlRegisterNodeRequest
  include Beefcake::Message
end

class ControlRegisterNodeResponse
  include Beefcake::Message
end

class ControlRegisterNodeRequest
  required :instance, ControlNodeInstance, 1
end

class ControlRegisterNodeResponse
  required :code, ControlMessage::Code, 1, :default => ControlMessage::Code::CODE_OKAY
  optional :message, :string, 2
end
