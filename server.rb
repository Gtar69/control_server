require 'eventmachine'
require 'redis'
require "beefcake"
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

class ControlServer < EM::Connection

  @@connect_hash = Hash.new

  def post_init
    p "-- someone connected to the control server!"
    start_tls :private_key_file => './atgames.key', :cert_chain_file => './atgames.crt', :verify_peer => false
    port, ip = Socket.unpack_sockaddr_in(get_peername)
    @ip = ip
    @control_node_port = port.to_s
    ip_with_port = ip + ":" + port.to_s
    @@connect_hash[ip_with_port] = self
  end

  def receive_data(data)
    begin
      h =  data.unpack('NN')
      header = h[0]
      content_length = h[1]
      str = 'NNa' << content_length.to_s
      hh = data.unpack(str)
      content = hh[2]
    rescue
    end
    case header
    when ControlMessage::Type::TYPE_REGISTER_NODE_REQUEST
      p "rcv prepare register request"
      register_request= ControlRegisterNodeRequest.decode(content)
      cast_port = register_request.streamer.port.to_s
      version = register_request.node.version
      mac = register_request.node.mac_address
      priavte_ip = register_request.node.local_address
      p @ip
      p @control_node_port
      $con.query( "INSERT INTO `servernodes` (`created_at`, `updated_at`,
        `ip_address`,`control_node_port`,`cast_port`,`status`,
        `name`,`version`,`private_ip_add`)
        VALUES ( '#{Time.now}', '#{Time.now}','#{@ip}','#{@control_node_port}',
        '#{cast_port}','Available','#{mac}', '#{version}','#{priavte_ip}')")
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
        opts = {"user_id" => stop_request.user_id, "game_id" => stop_request.game_id}
        handle_send("stop_game_response", opts)
      else
        p "error"
      end
    else
      p "error"
    end
  end

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
      begin
        control_type = ControlMessage::Type::TYPE_PLAY_GAME_REQUEST
        game = Game.new
        game.id = opts["game_id"]
        game.name = opts["name"]
        game.process_name = opts["process_name"]
        game.launch_command = opts["launch_command"]
        game.shutdown_command = opts["shutdown_command"]
        game.backup = []

        back_up = GameBackup.new
        back_up.name = opts["back_up_name"]
        back_up.root = opts["back_up_root"]
        back_up.entries = opts["back_up_entries"]
        back_up.remove_entries = opts["back_up_remove_entries"]
        game.backup<< back_up

        storage = Storage.new
        storage.host = "54.176.237.32"
        storage.port = 990
        storage.username = "atgamesftp"
        storage.password = "atgamescloud"
        storage.secure = true

        play_request = ControlPlayGameRequest.new
        play_request.user_id = opts["user_id"]
        play_request.has_backup = opts["update_saved"]
        play_request.game = game
        play_request.storage = storage
      rescue Exception => ex
        puts "An error of type #{ex.class} happened, message is #{ex.message}"
      end
      play_array = []
      play_array << control_type << play_request.encode.length << play_request.encode
      str = 'NNa' << play_request.encode.length.to_s
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

  $con.query("Truncate table `servernodes`")

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
