#!mruby
#GR-CITRUS Version 2.50

# GR-CITRUS and WA-MIKAN MQTT Client Sample program
# http://gadget.renesas.com/ja/product/citrus.html
# http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/mqtt-v3.1.1.html

WIFI_SSID = "enter_your_wifi_ssid"
WIFI_PASS = "enter_your_wifi_pass"

# MODE – Make IoT a reality for your business
# https://www.tinkermode.com/
MQTT_SERVER = "mqtt.tinkermode.com"
MQTT_PORT = 1883    # TCP=1883, SSL=8883
MQTT_KEEP_ALIVE = 60
USER_NAME = "enter_your_device_id"
PASSWORD = "enter_your_device_API_key"
PUB_TOPIC = "/devices/#{USER_NAME}/event" 
SUB_TOPIC = "/devices/#{USER_NAME}/command"

ESP8266_EN = 5
LIGHT_LED = 17
BUTTON_PIN = 10

DEBUG = false

def  wait_response(expected_value, timeout)
    end_time = millis() + timeout

    result = ""    
    while end_time > millis() do
        if @wifi.available() > 0
            result = result + @wifi.read()
            if result.include?(expected_value)
                puts result if DEBUG
                return true 
            end
            delay 10
        end
    end

    puts result if DEBUG
    return false
end

def dump_packet_string(packet)
    puts packet.length
    debug = ""
    packet.chars { |ch|  debug += ch.ord.to_s(16) + " " }
    puts debug
end

def build_mqtt_connect_packet(params)
    keep_alive = params[:keep_alive] || 60
    client_id = params[:client_id] || ""
    will_topic = params[:will_topic] || ""
    will_msg = params[:will_msg] || ""
    user_name = params[:user_name] || ""
    password = params[:password] || ""

    # Calculate Remaining Length
    remaining_length = 10   # header length 
    remaining_length += (2 + client_id.length)
    remaining_length += (2 + will_topic.length + 2 + will_msg.length) if will_topic.length > 0 && will_msg.length > 0
    remaining_length += (2 + user_name.length + 2 + password.length) if user_name.length > 0 && password.length > 0

    # 3.1 CONNECT – Client requests a connection to a Server
    # 3.1.1  Fixed header
    # MQTT Control Packet type
    result = 0x10.chr

    # Remaining Length -  see section 2.2.3.
    len = remaining_length
    loop do
        encoded_byte = len % 128
        len = len.div 128
        encoded_byte = encoded_byte | 128 if len > 0
        result += encoded_byte.chr
        break unless len > 0
    end

    # 3.1.2 Variable header
    # Protocol Name
    result += 0x00.chr
    result += 0x04.chr
    result += 'MQTT'

    # Protocol Level - MQTT 3.1.1
    result += 0x04.chr

    # Connect Flags
    connect_flag = 0x02
    connect_flag |= 0x04 if (will_topic.length > 0 && will_msg.length > 0)
    connect_flag |= 0xC0 if (user_name.length > 0 && password.length > 0)
    result += connect_flag.chr
    
    # Keep Alive
    result += 0x00.chr
    result += keep_alive.chr

    # 3.1.3 Payload
    # 3.1.3.1 Client Identifier
    result += 0x00.chr
    result += client_id.length.chr
    result += client_id

    # 3.1.3.2 Will Topic
    # 3.1.3.3 Will Message
    if (will_topic.length > 0 && will_msg.length > 0)
        result += 0x00.chr
        result += will_topic.length.chr
        result += will_topic
        result += 0x00.chr
        result += will_msg.length.chr
        result += will_msg
    end

    # 3.1.3.4 User Name
    # 3.1.3.5 Password
    if (user_name.length > 0 && password.length > 0)
        result += 0x00.chr
        result += user_name.length.chr
        result += user_name
        result += 0x00.chr
        result += password.length.chr
        result += password
    end

    dump_packet_string(result) if DEBUG
    return result
end

def build_mqtt_publish_packet(params)
    topic = params[:topic] || ""
    message = params[:message] || ""

    # 3.3 PUBLISH – Publish message
    # 3.3.1 Fixed header
    result = 0x30.chr   #  DUP=0, QoS=0 (At most once delivery), RETAIN=0
    result += (topic.length + message.length + 2).chr

    # 3.3.2  Variable header
    # 3.3.2.1 Topic Name
    result += 0x00.chr
    result += topic.length.chr
    result += topic

    # 3.3.3 Payload
    result += message

    dump_packet_string(result) if DEBUG
    return result
end

def build_mqtt_subscribe_packet(params)
    topic = params[:topic] || ""

    # 3.8 SUBSCRIBE - Subscribe to topics
    # 3.8.1 Fixed header
    result = 0x82.chr
    result += (topic.length + 5).chr

    # 3.8.2 Variable header
    # Packet Identifier set to 0x1
    result += 0x00.chr
    result += 0x01.chr

    # 3.8.3 Payload
    # Length
    result += 0x00.chr
    result += topic.length.chr
    result += topic
    # topic.chars { |ch| result += ch.chr }

    # Requested QoS = 0
    result += 0x00.chr

    dump_packet_string(result) if DEBUG
    return result
end

def mqtt_request(packet, expected_value)
    @wifi.print("AT+CIPSEND=#{packet.length}\r\n")
    System.exit "AT+CIPSEND failed" unless wait_response("OK\r\n>", 5000)
    @wifi.print(packet)
    wait_response(expected_value, 10000) 
end

# setup
[ESP8266_EN, LIGHT_LED].each { |pin| pinMode(pin, OUTPUT) }
pinMode(BUTTON_PIN, INPUT_PULLUP)

puts "ESP8266 Reset..."
[LOW, HIGH].each do |value| 
    digitalWrite(ESP8266_EN, value)
    delay 500
end

puts "WiFi Connecting..."
@wifi = Serial.new(3,115200)
@wifi.print("AT+CWMODE=1\r\n")
System.exit "AT+CWMODE failed" unless wait_response("OK", 1000)

@wifi.print("AT+CWJAP=\"#{WIFI_SSID}\",\"#{WIFI_PASS}\"\r\n")
System.exit "AT+CWJAP failed" unless wait_response("OK", 10000)

if (MQTT_PORT == 1883)
    puts "TCP Start..."
    @wifi.print("AT+CIPSTART=\"TCP\",\"#{MQTT_SERVER}\",#{MQTT_PORT}\r\n")
    System.exit "AT+CIPSTART failed" unless wait_response("OK", 5000)
else
    puts "SSL Start..."
    @wifi.print("AT+CIPSSLSIZE=4096\r\n")
    System.exit "AT+CIPSSLSIZE failed" unless wait_response("OK", 1000)

    @wifi.print("AT+CIPSTART=\"SSL\",\"#{MQTT_SERVER}\",#{MQTT_PORT}\r\n")
    System.exit "AT+CIPSTART failed" unless wait_response("OK", 5000)
end

puts "MQTT Connect - #{MQTT_SERVER}"
packet = build_mqtt_connect_packet(keep_alive: MQTT_KEEP_ALIVE, user_name: USER_NAME, password: PASSWORD)
System.exit "CONNACK Fail" unless mqtt_request(packet, "+IPD")  # TODO: check the CONNACK Return Code
delay(100)

puts "MQTT Subscribe"
packet = build_mqtt_subscribe_packet(topic: SUB_TOPIC)
System.exit "SUBACK Fail" unless mqtt_request(packet, "+IPD")  # TODO: check the SUBACK Return Code
delay(100)

puts "Topic - #{SUB_TOPIC}"

@lastmillis = millis();

one_sec_ticker = 0
led_state = 1

loop do
    now = millis()
    @lastmillis = now if (now - @lastmillis) < 0

    if (now - @lastmillis) > 1000
        @lastmillis = now;

        one_sec_ticker += 1
        led(led_state)
        led_state = (1 - led_state)

        # PING
        if one_sec_ticker == MQTT_KEEP_ALIVE
            puts "MQTT PING"
            System.exit "PINGRESP Fail" unless mqtt_request((0xc0.chr + 0x00.chr), "+IPD")  # TODO: check the Return Code
            one_sec_ticker = 0
        end
    end

    # PUBLISH
    if digitalRead(BUTTON_PIN) == 0
        puts "MQTT PUBLISH"
        packet = build_mqtt_publish_packet(topic: PUB_TOPIC, message: "{ \"eventType\": \"test\", \"eventData\": { \"value\": \"#{now}\" } }")
        System.exit "PUBLISH Fail" unless mqtt_request(packet, "SEND OK")
    end
    
    # Check Subscribe
    if @wifi.available() > 0
        receive_message = ""
        while @wifi.available() > 0 do
            receive_message += @wifi.read()
            delay 50    # a little hacky but  this may be the best...
        end

        if receive_message.include?(SUB_TOPIC)
            puts "MQTT PUBACK"
            System.exit "PUBACK Fail" unless mqtt_request((0x40.chr + 0x02.chr), "SEND OK")

            # do something
            if receive_message.include?('switch":0')
                puts "switch: off"
                digitalWrite(LIGHT_LED, LOW)
             elsif receive_message.include?('switch":1')
                puts "switch: on" 
                digitalWrite(LIGHT_LED, HIGH)
            end

        end
    end

end

