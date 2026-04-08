#!/bin/bash

# Set your paths for bbb-lti-broker and bbb-app-rooms before starting
# Tip: use "$HOME" instead of "~"
lti_broker_path=../bbb-lti-broker # ex: "$HOME/Projects/bbb-lti-broker"
app_rooms_path=.  #     "$HOME/Projects/bbb-app-rooms"

env="development"
dc_service="app"

# to connect to moodle.h.mconf.dev using LTI 1.3
# If you need to use the Saltire test app, update these variables
issuer="https://moodle.h.mconf.dev"
client_id="kFQFqSRXyW88NyC"
key_set_url="https://moodle.h.mconf.dev/mod/lti/certs.php"
auth_token_url="https://moodle.h.mconf.dev/mod/lti/token.php"
auth_login_url="https://moodle.h.mconf.dev/mod/lti/auth.php"

# to connect to any app using LTI 1.0
my_key="my-key"
my_secret="my-secret"

# Used on the oauth flow between broker and rooms
my_internal_key="rooms-internal-key"
my_internal_secret="rooms-internal-secret"

redb=`tput setaf 1; tput setab 0`
greenb=`tput setaf 2; tput setab 0`
yellowb=`tput setaf 3; tput setab 0`
reset=`tput sgr0`

if [ -z $lti_broker_path ] || [ -z $app_rooms_path ];
then
  echo "Edit the script and set your paths for" \
     "${greenb}bbb-lti-broker${reset} and"\
     "${yellowb}bbb-app-rooms${reset} before starting (first 2 lines of code)."
  exit 1
fi

port0="3000"
port1="3001"

start_localtunnel() {
  lt_dir="$HOME/.config/localtunnel"
  lt_log0="$lt_dir/broker.log"
  lt_log1="$lt_dir/rooms.log"
  mkdir -p "$lt_dir"

  if ! command -v npx >/dev/null 2>&1;
  then
    echo "npx not found. Install Node.js and npm before running this script."
    exit 1
  fi

  lt_is_running=false
  if pgrep -af "localtunnel --port $port0|localtunnel --port $port1" >/dev/null;
  then
    lt_is_running=true
  fi

  if [ "$lt_is_running" = true ];
  then
    read -p "localtunnel appears to be running, do you want to kill it? [y/N] " proceed
    if [ "${proceed,,}" = "y" ];
    then
      pkill -f "localtunnel --port $port0|localtunnel --port $port1"
      sleep 1s
    else
      echo "exiting"
      exit 1
    fi
  fi

  rm -f "$lt_log0" "$lt_log1"
  npx --yes localtunnel --port "$port0" > "$lt_log0" 2>&1 &
  npx --yes localtunnel --port "$port1" > "$lt_log1" 2>&1 &

  address0_cmd="grep -aoP 'https://[^ ]+\.(loca\.lt|localtunnel\.me)' $lt_log0 | tail -n 1"
  address1_cmd="grep -aoP 'https://[^ ]+\.(loca\.lt|localtunnel\.me)' $lt_log1 | tail -n 1"

  address0=$(eval "$address0_cmd")
  address1=$(eval "$address1_cmd")
  while [ -z "$address0" ] || [ -z "$address1" ];
  do
    address0=$(eval "$address0_cmd")
    address1=$(eval "$address1_cmd")
    echo "Waiting for localtunnel to start..."
    sleep 1s
  done

  address0="${address0#https://}"
  address1="${address1#https://}"

  echo
  echo "localtunnel started"
  echo "Forwarding Broker: http://localhost:${greenb}$port0${reset} -> https://${greenb}$address0${reset}"
  echo "Forwarding Rooms: http://localhost:${yellowb}$port1${reset} -> https://${yellowb}$address1${reset}"
}

update_tunnel_addresses() {
  broker_env="$lti_broker_path/.env"
  rooms_env="$app_rooms_path/.env.development.local"

  echo
  replace_key_value $broker_env "URL_HOST" $address0 ${greenb}
  replace_key_value $broker_env "DEFAULT_LTI_TOOL" "rooms" ${greenb}
  replace_key_value $rooms_env "URL_HOST" $address1 ${yellowb}
  replace_key_value $rooms_env "OMNIAUTH_BBBLTIBROKER_SITE" "https://$address0" ${yellowb}

  echo
  echo "Check if everything is alright."
  read -p "This will update the ${greenb}bbb-lti-broker${reset} database. Proceed? [y/N] " proceed
  echo
  if [ "${proceed,,}" = "y" ];
  then
    broker_dc=$lti_broker_path/docker-compose.yml
    docker compose -f $broker_dc run --rm $dc_service bundle exec rake "db:apps:add_or_update[rooms,https://$address1/rooms/auth/bbbltibroker/callback,$my_internal_key,$my_internal_secret]"
    docker compose -f $broker_dc run --rm $dc_service bundle exec rake "db:keys:add[$my_key,$my_secret]"
    # uncomment these if you need a LTI 1.3 tool
    # docker compose -f $broker_dc run --rm $dc_service bundle exec rake "db:registration:create[$issuer,$client_id,$key_set_url,$auth_token_url,$auth_login_url]"
    # docker compose -f $broker_dc run --rm $dc_service bundle exec rake db:registration:url[rooms]
  else
    echo "exiting"
    exit 1
  fi
}

replace_key_value() {
  file=$1
  key=$2
  addr=$3
  if [ $# -ge 4 ]
  then
    color=$4
  else
    color=''
  fi
  echo "Replacing $key=${color}$addr${reset} in ${color}$(readlink -e $file)${reset}"
  # replace '/' for '\/' in $addr
  addr=$(echo $addr | sed 's/\//\\\//g')
  # Find line starting by $key= (any space to the left of it is acceptable)
  # In this line, find all groups that does NOT contain '=', '#', ' ' or '\t'.
  # Select the group 2 and replace for $addr
  # Ex:
  # 11111111 222222222222222 ...
  # URL_HOST=abcdef.ngrok.io # SOME COMMENT
  # group 1: URL_HOST
  # group 2: abcdef.ngrok.io
  # Replace group 2 with $addr, so it becomes:
  # URL_HOST=$addr # SOME COMMENT
  sed -i "/^[\t ]*$key=/s/[\t ]*[^=#\t ]*/$addr/2" $file
}

start_localtunnel
update_tunnel_addresses
