## Generated from atg/cloud/play.proto for atg.cloud
require "beefcake"
require "./game.pb.rb"
require "./storage.pb.rb"


class ControlPlayGameRequest
  include Beefcake::Message
end

class ControlPlayGameResponse
  include Beefcake::Message
end

class ControlPlayGameRequest
  required :user_id, :int32, 1
  required :game, Game, 2
  required :has_backup, :bool, 3, :default => false
  required :storage, Storage, 4
end

class ControlPlayGameResponse
  required :user_id, :int32, 1
  required :game_id, :int32, 2
  required :code, ControlMessage::Code, 3, :default => ControlMessage::Code::CODE_OKAY
  optional :message, :string, 4
end
