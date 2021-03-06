## Generated from atg/cloud/control.proto for atg.cloud
require "beefcake"


class ControlMessage
  include Beefcake::Message

  module Constant
    HEADER_LENGTH = 8
  end

  module Type
    TYPE_UNKNOWN = 0
    TYPE_REGISTER_NODE_REQUEST = 264900864
    TYPE_REGISTER_NODE_RESPONSE = 264900866
    TYPE_HEARTBEAT_REQUEST = 265949440
    TYPE_HEARTBEAT_RESPONSE = 265949444
    TYPE_PREPARE_GAME_REQUEST = 268047105
    TYPE_PREPARE_GAME_RESPONSE = 268047106
    TYPE_PLAY_GAME_REQUEST = 268047107
    TYPE_PLAY_GAME_RESPONSE = 268047108
    TYPE_STOP_GAME_REQUEST = 268047109
    TYPE_STOP_GAME_RESPONSE = 268047110
  end

  module Code
    CODE_OKAY = 0
    CODE_INVALID_USER_ID_OR_GAME_ID = 268513281
    CODE_INVALID_MESSAGE_ACCORDING_TO_CURRENT_STATE = 268513282
    CODE_NO_SUCH_GAME = 268513283
    CODE_MISSING_BACKUP_DATA = 268513284
    CODE_FAILED_TO_DOWNLOAD_BACKUP_DATA = 268513285
    CODE_FAILED_TO_LAUNCH_GAME = 268513286
    CODE_FAILED_TO_LAUNCH_EXECUTABLE = 268513287
    CODE_FAILED_TO_UPLOAD_BACKUP_DATA = 268513288
    CODE_FAILED_TO_PACK_BACKUP_DATA = 268513289
    CODE_FAILED_TO_UNPACK_BACKUP_DATA = 268513290
    CODE_FAILED_TO_STOP_GAME = 268513291
    CODE_FAILED_TO_STOP_EXECUTABLE = 268513292
    CODE_INVALID_GAME_NAME = 268513293
    CODE_INVALID_GAME_LAUNCH_COMMAND = 268513294
    CODE_INVALID_GAME_SHUTDOWN_COMMAND = 268513295
    CODE_INVALID_GAME_BACKUP_ROOT = 268513296
    CODE_INVALID_GAME_BACKUP_ENTRIES = 268513297
    CODE_FAILED_TO_REMOVE_DIRECTORIES = 268513298
    CODE_USER_ALREADY_LOGIN = 268513299
    CODE_INVALID_MAC_ADDRESS = 268513300
    CODE_INVALID_PORT = 268513301
    CODE_INVALID_IP_ADDRESS = 268513302
    CODE_INVALID_VERSION = 268513303
  end
end

class ControlNodeInstance
  include Beefcake::Message
end

class StreamerInstance
  include Beefcake::Message
end

class ControlMessage
end

class ControlNodeInstance
  required :version, :string, 1
  required :mac_address, :string, 2
  required :local_address, :string, 3
end

class StreamerInstance
  required :version, :string, 1
  required :port, :uint32, 2, :default => 0
end
