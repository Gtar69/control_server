## Generated from atg/cloud/game.proto for atg.cloud
require "beefcake"


class Game
  include Beefcake::Message
end

class Game
  required :id, :int32, 1, :default => 0
  required :name, :string, 2
  required :package_name, :string, 3
  required :launchable_activity, :string, 4
  required :save_game_root, :string, 5
  required :save_game_location, :string, 6
  repeated :save_game_entries, :string, 7
  repeated :remove_save_game_entries, :string, 8
end
