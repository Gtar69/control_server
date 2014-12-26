## Generated from atg/cloud/prepare.proto for atg.cloud
require "beefcake"


class ControlPrepareGameRequest
  include Beefcake::Message
end

class ControlPrepareGameResponse
  include Beefcake::Message
end

class ControlPrepareGameRequest
  required :user_id, :int32, 1
  required :game_id, :int32, 2
end

class ControlPrepareGameResponse
  required :user_id, :int32, 1
  required :game_id, :int32, 2
  required :code, ControlMessage::Code, 3, :default => ControlMessage::Code::CODE_OKAY
  optional :message, :string, 4
end
