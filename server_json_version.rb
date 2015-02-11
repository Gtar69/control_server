require 'eventmachine'
require 'redis'
require 'mysql'
require 'json'
require 'timers'

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
    @timers = Timers::Group.new
    @timers.every(15) do
      p " #{Time.now} on post init: ready to disconnect"
      self.unbind
    end
    Thread.new { @timers.wait }
  end

  def receive_data data

    begin
      parse_data = JSON.parse(data)

      case parse_data["method"]
      when "registerNodeRequest"
        p "register node request information"
        packages = parse_data["params"]["packages"]
        version = parse_data["params"]["node"]["version"]
        mac_address = parse_data["params"]["node"]["macAddress"]
        private_ip = parse_data["params"]["node"]["localAddress"]
        cast_port = parse_data["params"]["streamer"]["port"]
        streamer_version = parse_data["params"]["streamer"]["version"]
        $con.query( "INSERT INTO `servernodes` (`created_at`, `updated_at`,`ip_address`,
          `control_node_port`,`cast_port`,`status`,`name`,`version`,`private_ip_add`, `packages`,`streamer_version`)
          VALUES ( '#{Time.now}', '#{Time.now}','#{@ip}','#{@control_node_port}',
          '#{cast_port}','Available','#{mac_address}', '#{version}','#{private_ip}', '#{packages}', '#{streamer_version}')")
        handle_send("register_response")
      when "heartbeatRequest"
        p "heartbeat request info from #{@ip}:#{@control_node_port}"
        @timers.pause
        @timers = Timers::Group.new
        @timers.every(15) do
          p " #{Time.now} in heartbeat request => ready to disconnect"
          self.unbind
        end
        Thread.new { @timers.wait }
        handle_send("heartbeat_response")
      when "prepareGameResponse"
        #ok / fail condition
        p "rcv prepare response"
        p parse_data
        user_id = parse_data["params"]["userId"]
        $con.query("UPDATE `status_checks` SET `status` = 'notify_to_play',`updated_at` = '#{Time.now}'
          WHERE `status_checks`.`id` = #{user_id}")
      when "playGameResponse"
        p "rcv play repsponse"
        p parse_data
        user_id = parse_data["params"]["userId"]
        $con.query("UPDATE `status_checks` SET `status` = 'playing_game_now',
          `updated_at` = '#{Time.now}' WHERE `status_checks`.`id` = #{user_id}")

      when "stopGameResponse"
        $con.query("UPDATE `servernodes` SET `status` = 'Available',
          `updated_at` = '#{Time.now}', `user_id` = NULL, `product_id` = NULL
          WHERE `servernodes`.`control_node_port` = #{@control_node_port}")

      when "stopGameRequest"
        user_id = parase_data["data"]["userId"]
        $con.query("UPDATE `status_checks` SET `status` = 'stop_game_from_node',
            `updated_at` = '#{Time.now}' WHERE `status_checks`.`id` = #{a}")
        opts = {"user_id" => parase_data["data"]["userId"], "game_id" => parase_data["params"]["gameId"]}
        handle_send("stop_game_response", opts)
      else
      end
    rescue Exception => ex
      puts "An error of type #{ex.class} happened, message is #{ex.message}"
    end
  end




  def handle_send(condition, opts = {})
    begin
      case condition
      when "register_response"
        p 'send register response'
        response = { method: "registerNodeResponse", data: {code: 200, message: "what"}}
        send_data(response.to_json)
      when "heartbeat_response"
        response = { method: "heartbeatResponse"}
        send_data(response.to_json)
      when "prepare_request"
        p 'send prepare'
        storage = { host: "54.176.73.176",port: 990,username: "atgamesftp",password: "atgamescloud",
          secure: { enabled: true, validation: false}, timeout: { connection: 10, operation: 15}}
        params = { userId: opts["user_id"], gameId: opts["game_id"], synchronizeRequired: opts["update_saved"],
          storage: storage}
        response = { method: "prepareGameRequest", params: params}
        send_data(response.to_json)
      when "handle_play_game"
        p 'send play'
        backup = [name: opts["back_up_name"], root: opts["back_up_root"],
          entries: opts["back_up_entries"], removeEntries: opts["back_up_remove_entries"]]

        game = { id: opts["game_id"], name: opts["name"], process: opts["process_name"],
          backup: backup,
          commands: {launch: opts["launch_command"], shutdown: opts["shutdown_command"]} }
        response = { method: "playGameRequest", params: {userId: opts["user_id"], game: game} }
        send_data(response.to_json)
      when "stop_game"
        response = { method: "stopGameRequest", params: {userId: opts["user_id"], gameId: opts["game_id"]}}
        p response.to_json
        send_data(response.to_json)
      when "stop_game_response"
        data = { code: 200, message: "what", userId: opts["user_id"], gameId: opts["game_id"]}
        response = { method: "stopGameResponse", data: data}
      else
      end
    rescue Exception => ex
      puts "An error of type #{ex.class} happened, message is #{ex.message}"
    end
  end

  def unbind
    $con.query("DELETE FROM `servernodes` WHERE `servernodes`.`ip_address`= '#{@ip}'
      AND `servernodes`.`control_node_port`= '#{@control_node_port}' ")
    p "-- #{@ip}:#{@control_node_port} disconnected from the echo server!"
  end

  def self.connect_hash
    @@connect_hash
  end

end


EventMachine.run do

  #EventMachine.heartbeat_interval
  p "control server start up"
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
