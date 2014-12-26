## Generated from atg/cloud/stop.proto for atg.cloud
require "beefcake"


class ControlStopGameRequest
  include Beefcake::Message
end

class ControlStopGameResponse
  include Beefcake::Message
end

class ControlStopGameRequest
  required :user_id, :int32, 1
  required :game_id, :int32, 2
end

class ControlStopGameResponse
  required :user_id, :int32, 1
  required :game_id, :int32, 2
  required :code, ControlMessage::Code, 3, :default => ControlMessage::Code::CODE_OKAY
  optional :message, :string, 4
end
