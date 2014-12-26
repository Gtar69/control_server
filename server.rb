require 'eventmachine'
require 'redis'
require './control.pb'
require './prepare.pb'
require './play.pb'
require './game.pb'
require './stop.pb'
require './storage.pb'
require './register.pb'
require './heartbeat.pb'
require 'mysql'
require 'json'

class ControlServer < EventMachine::Connection

  @@connect_hash = Hash.new

  def post_init
    p "-- someone connected to the control server!"
    port, ip = Socket.unpack_sockaddr_in(get_peername)
    @ip = ip
    @control_node_port = port.to_s
    ip_with_port = ip + ":" + port.to_s
    @@connect_hash[ip_with_port] = self
  end

  def receive_data(data)
    h =  data.unpack('NN')
    header = h[0]
    content_length = h[1]
    str = 'NNa' << content_length.to_s
    hh = data.unpack(str)
    content = hh[2]
    case header
    when ControlMessage::Type::TYPE_REGISTER_NODE_REQUEST
      #db servernode register
      p "rcv prepare register request"
      register_request= ControlRegisterNodeRequest.decode(content)
      a = register_request.instance.streamer_port.to_s
      p @ip
      p @control_node_port
      $con.query( "INSERT INTO `servernodes` (`created_at`, `updated_at`,
        `ip_address`,`control_node_port`,`cast_port`,`status`)
        VALUES ( '#{Time.now}', '#{Time.now}','#{@ip}','#{@control_node_port}',
        '#{a}','Available')")
      handle_send("register_response")
    when ControlMessage::Type::TYPE_HEARTBEAT_REQUEST
      handle_send("heartbeat_response")
    when ControlMessage::Type::TYPE_PREPARE_GAME_RESPONSE
      p 'db status prepare_ok => notify_to_play'
      prepare_response = ControlPrepareGameResponse.decode(content)
      a = prepare_response.user_id
      $con.query("UPDATE `status_checks` SET `status` = 'notify_to_play',
        `updated_at` = '#{Time.now}' WHERE `status_checks`.`id` = #{a}")
    when ControlMessage::Type::TYPE_PLAY_GAME_RESPONSE
      p 'db status playing_game_now => playing_game_now'
      play_response= ControlPlayGameResponse.decode(content)
      a = play_response.user_id
      $con.query("UPDATE `status_checks` SET `status` = 'playing_game_now',
        `updated_at` = '#{Time.now}' WHERE `status_checks`.`id` = #{a}")
    when ControlMessage::Type::TYPE_STOP_GAME_RESPONSE
      p 'rcv stop game response db status stop_game'
      stop_response= ControlStopGameResponse.decode(content)
      if stop_response.code ==  ControlMessage::Code::CODE_OKAY
        $con.query("UPDATE `servernodes` SET `status` = 'Available',
          `updated_at` = '#{Time.now}', `user_id` = NULL, `product_id` = NULL
          WHERE `servernodes`.`control_node_port` = #{@control_node_port}")
      else
      end
    when ControlMessage::Type::TYPE_STOP_GAME_REQUEST
      p "stop from andorid node /status stop_game_from_node"
      stop_request= ControlStopGameResponse.decode(content)
      if stop_request.code =  ControlMessage::Code::CODE_OKAY
        a = stop_request.user_id
        $con.query("UPDATE `status_checks` SET `status` = 'stop_game_from_node',
          `updated_at` = '#{Time.now}' WHERE `status_checks`.`id` = #{a}")
        #$con.query("UPDATE `servernodes` SET `status` = 'Available',
        #  `updated_at` = '#{Time.now}', `user_id` = NULL, `product_id` = NULL
        #  WHERE `servernodes`.`control_node_port` = #{@control_node_port}")
        opts = {"user_id" => stop_request.user_id, "game_id" => stop_request.game_id}
        p opts
        handle_send("stop_game_response", opts)
      else
      end
    else
      #error handling
      p "error"
    end
  end

  #UPDATE `servernodes` SET `name` = 'ttt', `updated_at` = '2014-12-23 10:30:41'
  #WHERE `servernodes`.`id` = 19
  ## UPDATE `status_checks` SET `status` = 'test',
  #{#}`updated_at` = '2014-12-24 08:26:39' WHERE `status_checks`.`id` = 1
 # DELETE FROM `servernodes` WHERE `servernodes`.`id` = 16 AND `servernodes`.`status` = 'Dump'

  def unbind
    #port, ip = Socket.unpack_sockaddr_in(get_peername)

    $con.query("DELETE FROM `servernodes` WHERE `servernodes`.`ip_address`= '#{@ip}'
      AND `servernodes`.`control_node_port`= '#{@control_node_port}' ")
    puts "-- #{@ip}:#{@control_node_port} disconnected from the echo server!"
  end

  def self.connect_hash
    @@connect_hash
  end

  def handle_send(condition, opts = {})
    case condition
    when "register_response"
      p "sending TYPE_REGISTER_NODE_RESPONSE to node"
      control_type = ControlMessage::Type::TYPE_REGISTER_NODE_RESPONSE
      register_response = ControlRegisterNodeResponse.new
      register_response.code = ControlMessage::Code::CODE_OKAY
      register_array = []
      register_array << control_type << register_response.encode.length <<
          register_response.encode
      str = 'NNa' << register_response.encode.length.to_s
      send_data(register_array.pack(str))
    when "heartbeat_response"
      #p "send TYPE_HEARTBEAT_RESPONSE to node"
      control_type = ControlMessage::Type::TYPE_HEARTBEAT_RESPONSE
      heart_array = []
      heart_array << control_type << 0
      send_data(heart_array.pack('NN'))
    when "prepare_request"
      p "sending TYPE_PREPARE_GAME_REQUEST to node => "
      control_type = ControlMessage::Type::TYPE_PREPARE_GAME_REQUEST
      prepare_request = ControlPrepareGameRequest.new
      prepare_request.user_id = opts["user_id"]
      prepare_request.game_id = opts["game_id"]
      prepare_array = []
      prepare_array << control_type << prepare_request.encode.length << prepare_request.encode
      str = 'NNa' << prepare_request.encode.length.to_s
      send_data(prepare_array.pack(str))
    when "handle_play_game"
      p "sending TYPE_PLAY_GAME_REQUEST to node => "
      control_type = ControlMessage::Type::TYPE_PLAY_GAME_REQUEST

      game = Game.new
      game.id = opts["game_id"]
      game.name = opts["name"]
      game.package_name = opts["package_name"]
      game.launchable_activity = opts["launchable_activity"]
      game.save_game_root = opts["save_game_root"]
      game.save_game_location = opts["save_game_location"]
      game.save_game_entries = opts["save_game_entries"]
      game.remove_save_game_entries = opts["remove_save_game_entries"]

      storage = Storage.new
      storage.host = "54.176.237.32"
      storage.port = 990
      storage.username = "atgamesftp"
      storage.password = "atgamescloud"
      storage.secure = true

      play_request = ControlPlayGameRequest.new
      play_request.user_id = opts["user_id"]
      play_request.update_saved = opts["update_saved"]
      play_request.game = game
      play_request.storage = storage

      play_array = []
      play_array << control_type << play_request.encode.length << play_request.encode
      str = 'NNa' << play_request.encode.length.to_s

      p play_array
      send_data(play_array.pack(str))
    when "stop_game"
      p "sending TYPE_STOP_GAME_REQUEST to node => "
      control_type = ControlMessage::Type::TYPE_STOP_GAME_REQUEST
      stop_request = ControlStopGameRequest.new
      stop_request.user_id = opts["user_id"]
      stop_request.game_id = opts["game_id"]
      stop_array = []
      stop_array << control_type << stop_request.encode.length << stop_request.encode
      str = 'NNa' << stop_request.encode.length.to_s
      send_data(stop_array.pack(str))
    when "stop_game_response"
      p "sending TYPE_STOP_GAME_RESPONSE to node => "
      control_type = ControlMessage::Type::TYPE_STOP_GAME_RESPONSE
      stop_response = ControlStopGameResponse.new
      stop_response.user_id = opts["user_id"]
      stop_response.game_id = opts["game_id"]
      stop_response.code = ControlMessage::Code::CODE_OKAY
      p stop_response
      stop_array = []
      stop_array << control_type << stop_response.encode.length << stop_response.encode
      str = 'NNa' << stop_response.encode.length.to_s
      send_data(stop_array.pack(str))
      #p "clean servernode"
      #$con.query("UPDATE `servernodes` SET `status` = 'Available',
      #  `updated_at` = '#{Time.now}', `user_id` = NULL, `product_id` = NULL
      #  WHERE `servernodes`.`control_node_port` = #{@control_node_port}")
    else
      p "do nothing"
    end
  end


end

EventMachine.run do
  p "tcp start up"

  begin
    $con = Mysql.new 'localhost', 'chris', '12345678','Mgmt_Server_dev'
  rescue Mysql::Error => e
    puts e.errno
    puts e.error
  end

  $redis = Redis.new(:host => 'localhost', :port => 6379)

  Thread.new do
    $redis.subscribe('rails_em_channel', 'ruby-lang') do |on|
      on.message do |channel, msg|
        p "redis send sth to me"
        p msg
        parse_msg = JSON.parse(msg)
        conn = ControlServer.connect_hash
        conn[parse_msg["ip_with_port"]].handle_send(parse_msg["request"], parse_msg)
      end
    end
  end

  EventMachine.start_server "0.0.0.0", 10000, ControlServer

end
