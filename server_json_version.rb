require 'eventmachine'
require 'redis'
require 'mysql'
require 'json'
require 'timers'
require 'active_record'

class ControlServer < EM::Connection

  @@connect_hash = Hash.new

  def post_init
    #Chris@0326 for local useage
    start_tls :private_key_file => './atgames.key', :cert_chain_file => './atgames.crt', :verify_peer => false
    port, ip = Socket.unpack_sockaddr_in(get_peername)
    @ip = ip
    @control_node_port = port.to_s
    ip_with_port = ip + ":" + port.to_s
    @@connect_hash[ip_with_port] = self
    # local usage end
    @timers = Timers::Group.new
    @timers.every(15) do
      p "#{Time.now} on post init: ready to disconnect"
      self.unbind
    end
    Thread.new { @timers.wait }
    #p "#{@ip}:#{@control_node_port} connected to the control server"
  end

  def receive_data data
    # Chris@0326 for load balancer proxy protocol
    if data.include? "PROXY"
      regex = /.+\r\n/
      @proxy_protocol = data.scan(regex)[0]
      p @proxy_protocol
      data = data.gsub(regex,"")
    elsif data.empty?
      data = "{\"method\":\"preRequest\"}"
    end


    begin
      parse_data = JSON.parse(data)
      case parse_data["method"]
      when "registerNodeRequest"
        begin
          p "#{Time.now} register node request information from #{@ip}:#{@control_node_port}"
          #Chris@0326 for load balancer proxy protocol
          #ip_regex = /\s\d+.\d+.\d+.\d+/
          #port_regex = /\s\d+\s/
          #@ip = @proxy_protocol.scan(ip_regex)[0].strip()
          #p @ip
          #@control_node_port = @proxy_protocol.scan(port_regex)[0].strip()
          #p @control_node_port
          #ip_with_port = @ip + ":" + @control_node_port
          #@@connect_hash[ip_with_port] = self
          name             = SecureRandom.uuid
          #remember change channel name in different instance
          channel          = "venice_fox"
          packages         = parse_data["params"]["packages"]
          version          = parse_data["params"]["node"]["version"]
          mac_addresses    = parse_data["params"]["node"]["macAddresses"]
          local_addresses  = parse_data["params"]["node"]["localAddresses"]
          platform         = parse_data["params"]["node"]["platform"]
          cast_port        = parse_data["params"]["streamer"]["port"]
          streamer_version = parse_data["params"]["streamer"]["version"]
          pattern = /(\')/
          packages.map! {|package| package.gsub(pattern){|match| "''" }}
          #register servernode
          $con.query( "INSERT INTO `servernodes` (`platform`,`name`,`created_at`, `updated_at`,`ip_address`, `channel`,
            `control_node_port`,`cast_port`,`status`,`mac_addresses`,`version`,`local_addresses`, `packages`,`streamer_version`)
            VALUES ( '#{platform}','#{name}','#{Time.now}', '#{Time.now}','#{@ip}','#{channel}','#{@control_node_port}',
            '#{cast_port}','Available','#{mac_addresses}','#{version}','#{local_addresses}','#{packages}','#{streamer_version}')")
          handle_send("register_response")
        rescue Exception => ex
          p "#{Time.now} An error of type #{ex.class} happened, message is #{ex.message}"
          response = { method: "registerNodeResponse", data: {code: 400, message: "#{ex.message}"}}
          $con.query("INSERT INTO `servernodes` (`name`,`ip_address`,`local_addresses`,`status`, `created_at`, `updated_at`)
            VALUES ('#{mac_addresses}','#{@ip}','#{local_addresses}','Registration Error', '#{Time.now}', '#{Time.now}')")
          send_data(response.to_json)
        end
      when "heartbeatRequest"
        begin
          #p "#{Time.now} heartbeat request info from #{@ip}:#{@control_node_port}"
          @timers.pause
          @timers = Timers::Group.new
          @timers.every(15) do
            p "#{Time.now} in heartbeat request => ready to disconnect"
            unbind
          end
          Thread.new { @timers.wait }
          handle_send("heartbeat_response")
        rescue Exception => ex
          p "#{Time.now} heartbeat request failed"
        end
      when "prepareGameResponse"
        if parse_data["data"]["code"] == 200
          p "#{Time.now} rcv prepare response from #{@ip}:#{@control_node_port}"
          user_id = parse_data["params"]["userId"]
          game_id = parse_data["params"]["gameId"]
          #0306 Chris add for handling error while user playing the game
          @user_id = user_id
          $con.query("UPDATE `status_checks` SET `status` = 'notify_to_play',`updated_at` = '#{Time.now}'
            WHERE `status_checks`.`user_id` = #{user_id}")


          #0429 Chris if response is initiated by api call, it shoule note as from: "api"
          # should notify xhtp api
          p      = Product.find(game_id)
          backup = [ name: p.back_up_name, root: p.back_up_root, entries: p.back_up_entries,
                     removeEntries: p.back_up_remove_entries ]
          game = {id: game_id, name: p.name, process: p.process_name, backup: backup,
                  commands: {launch: p.launch_command, shutdown: p.shutdown_command } }
          response = { method: "playGameRequest", params: {userId: user_id, game: game} }
          send_data(response.to_json)

        else
          p "#{Time.now} rcv #{parse_data["data"]["message"]} from #{@ip}:#{@control_node_port}"
          user_id = parse_data["params"]["userId"]
          #prepare fail handling
          $con.query("UPDATE `servernodes`  SET `status`='Preparation Error', `updated_at`='#{Time.now}'
            WHERE `servernodes`.`control_node_port` = '#{@control_node_port}'")
          $con.query("UPDATE `status_checks` SET `status` = 'fail_prepare',`updated_at` = '#{Time.now}'
            WHERE `status_checks`.`user_id` = #{user_id}")
        end
      when "playGameResponse"
        if parse_data["data"]["code"] == 200
          p "#{Time.now} rcv play repsponse from #{@ip}:#{@control_node_port}"
          user_id = parse_data["params"]["userId"]
          $con.query("UPDATE `status_checks` SET `status` = 'playing_game_now',`updated_at` = '#{Time.now}'
            WHERE `status_checks`.`user_id` = #{user_id}")
        else
          p "#{Time.now} rcv #{parse_data["data"]["message"]} from #{@ip}:#{@control_node_port}"
          user_id = parse_data["params"]["userId"]
          #play fail handling
          $con.query("UPDATE `servernodes`  SET `status`='Playing Error', `updated_at`='#{Time.now}'
            WHERE `servernodes`.`control_node_port` = '#{@control_node_port}'")
          $con.query("UPDATE `status_checks` SET `status` = 'fail_play',`updated_at` = '#{Time.now}'
            WHERE `status_checks`.`user_id` = #{user_id}")
        end

      when "stopGameResponse"
        if parse_data["data"]["code"] == 200
          p "#{Time.now} rcv stop repsponse from #{@ip}:#{@control_node_port}"
          $con.query("UPDATE `servernodes` SET `status` = 'Available',
            `updated_at` = '#{Time.now}', `user_id` = NULL, `product_id` = NULL
            WHERE `servernodes`.`control_node_port` = #{@control_node_port}")
        else
          #stop fail handling
          p "#{Time.nodeow} rcv stop #{parse_data["data"]["message"]} from #{@ip}:#{@control_node_port}"
          $con.query("UPDATE `servernodes` SET `status` = 'Stop Error',
            `updated_at` = '#{Time.now}' WHERE `servernodes`.`control_node_port` = #{@control_node_port}")
        end
      when "stopGameRequest"
        p "#{Time.now} rcv stop request from #{@ip}:#{@control_node_port}"
        begin
          user_id = parse_data["params"]["userId"]
          $con.query("UPDATE `status_checks` SET `status` = 'stop_game_from_node',`updated_at` = '#{Time.now}'
            WHERE `status_checks`.`user_id` = #{user_id}")
          opts = {"user_id" => parse_data["params"]["userId"], "game_id" => parse_data["params"]["gameId"]}
          handle_send("stop_game_response", opts)


        rescue Exception => ex
          p "An error of type #{ex.class} happened, message is #{ex.message}"
          $con.query("UPDATE `servernodes` SET `status` = 'Stop Request From Node Error',
            `updated_at` = '#{Time.now}' WHERE `servernodes`.`control_node_port` = #{@control_node_port}")
        end
      else
      end
    rescue Exception => ex
      p "An error of type #{ex.class} happened, message is #{ex.message}"
    end
  end




  def handle_send(condition, opts = {})
    begin
      case condition
      when "register_response"
        p Product.all
        p "#{Time.now} send register response to #{@ip}:#{@control_node_port}"
        node     = { timeout: {connection: 1000}, interval: {reconnect: 1000, heartbeat: 5000}, retry: {heartbeat: 3}}
        response = { method: "registerNodeResponse", data: {code: 200, message: "successful connection",node: node }}
        send_data(response.to_json)
      when "heartbeat_response"
        response = { method: "heartbeatResponse"}
        send_data(response.to_json)
      when "prepare_request"
        p "#{Time.now} send prepare request to #{@ip}:#{@control_node_port}"
        storage  = { host: "54.176.73.176",port: 990, username: "atgamesftp",password: "atgamescloud",
          secure: { enabled: true, validation: false}, timeout: { connection: 10000, operation: 0}}
        params   = { userId: opts["user_id"], gameId: opts["game_id"], synchronizeRequired: opts["update_saved"],
          storage: storage }
        response = { method: "prepareGameRequest", params: params}
        #p "prepare json format"
        #p response.to_json
        send_data(response.to_json)
      when "handle_play_game"
        p "#{Time.now} send play request to #{@ip}:#{@control_node_port}"
        backup = [name: opts["back_up_name"], root: opts["back_up_root"],
          entries: opts["back_up_entries"], removeEntries: opts["back_up_remove_entries"]]
        #p "play request"
        #p opts["back_up_entries"]
        #p opts["back_up_remove_entries"]
        game   = { id: opts["game_id"], name: opts["name"], process: opts["process_name"], backup: backup,
          commands: {launch: opts["launch_command"], shutdown: opts["shutdown_command"]} }
        response = { method: "playGameRequest", params: {userId: opts["user_id"], game: game} }
        #p "play game json format"
        #p response.to_json
        send_data(response.to_json)
      when "stop_game"
        p "#{Time.now} send stop request to #{@ip}:#{@control_node_port}"
        response = { method: "stopGameRequest", params: {userId: opts["user_id"], gameId: opts["game_id"]}}
        send_data(response.to_json)
      when "stop_game_response"
        p "#{Time.now} send stop response to #{@ip}:#{@control_node_port}"
        data     = { code: 200, message: "stop game response"}
        params   = { userId: opts["user_id"], gameId: opts["game_id"]}
        response = { method: "stopGameResponse", data: data, params: params}
        send_data(response.to_json)
      else
      end
    rescue Exception => ex
      p "An error of type #{ex.class} happened, message is #{ex.message}"
    end
  end

  def unbind
    begin
      close_connection
      # 0306 Chris disconnect not leave but dump
      $con.query("DELETE FROM `servernodes` WHERE `servernodes`.`ip_address`= '#{@ip}'
        AND `servernodes`.`control_node_port`= '#{@control_node_port}' ")
      #$con.query("UPDATE `servernodes` SET `status` = 'Disconnected',
      #  `updated_at` = '#{Time.now}' WHERE `servernodes`.`control_node_port` = #{@control_node_port}")
      if @user_id
        $con.query("UPDATE `status_checks` SET `status` = 'fail_connection',`updated_at` = '#{Time.now}'
          WHERE `status_checks`.`user_id` = #{@user_id}")
      end
      p "#{@ip}:#{@control_node_port} disconnected from the control server!"
    rescue Exception => ex
      p "#{Time.now} error happend in unbind between server and node"
      p "An error of type #{ex.class} happened, message is #{ex.message}"
    end
  end

  def self.connect_hash
    @@connect_hash
  end

end


EventMachine.run do
  p "#{Time.now} control server start up"
  begin
    $con = Mysql.new 'localhost', 'chris', '12345678','Mgmt_Server_dev'
  rescue Mysql::Error => e
    puts e.errno
    puts e.error
  end

  Dir["./rails_models/*.rb"].each {|file| require file }

  ActiveRecord::Base.establish_connection(
    adapter:  'mysql2', # or 'postgresql' or 'sqlite3'
    host:     'localhost',
    database: 'Mgmt_Server_dev',
    username: 'chris',
    password: '12345678'
  )


  #p Product.all

  #Chris@0327 delete servernode fro
  #$con.query("Truncate table `servernodes`")
  $con.query("DELETE FROM `servernodes` WHERE `servernodes`.`channel`= 'venice_fox'")
  $redis = Redis.new(:host => "localhost", :port => 6379)
  Thread.new do
    #Chris@0326 remember different channel name in different machines
    $redis.subscribe('venice_fox', 'ruby-lang') do |on|
      on.message do |channel, msg|
        parse_msg = JSON.parse(msg)
        conn      = ControlServer.connect_hash
        conn[parse_msg["ip_with_port"]].handle_send(parse_msg["request"], parse_msg)
      end
    end
  end

  EventMachine.start_server "0.0.0.0", 10000, ControlServer
end
