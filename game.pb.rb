## Generated from atg/cloud/game.proto for atg.cloud
require "beefcake"


class GameBackup
  include Beefcake::Message
end

class Game
  include Beefcake::Message
end

class GameBackup
  required :name, :string, 1
  required :root, :string, 2
  repeated :entries, :string, 3
  repeated :remove_entries, :string, 4
end

class Game
  required :id, :int32, 1, :default => 0
  required :name, :string, 2
  required :process_name, :string, 3
  required :launch_command, :string, 4
  required :shutdown_command, :string, 5
  repeated :backup, GameBackup, 6
end
