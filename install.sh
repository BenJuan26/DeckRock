#!/usr/bin/env bash
SCRIPT_DIR=$PWD

MC_DIR=$HOME/Minecraft
EXE_NAME="Minecraft.Windows.exe"
USER_ID=$(ls $HOME/.steam/steam/userdata)
SHORTCUTS_VDF=$HOME/.steam/steam/userdata/$USER_ID/config/shortcuts.vdf
MC_CONTENT=$MC_DIR/Content

wait_for_app_id() {
    echo "The script will now pause for you to add Minecraft as a non-Steam game."
    echo "The Content folder will now open. Right-click Minecraft.Windows.exe and click Add to Steam, then the script will continue."
    echo -n "Waiting for shortcut... "
    sleep 3
    xdg-open $MC_CONTENT
    APP_ID=
    while [ -z "$APP_ID" ]; do
        SHORTCUTS=$(python3 readsc/readsc.py $SHORTCUTS_VDF)
        APP_ID=$(echo $SHORTCUTS | jq -r ".shortcuts[] | select(.AppName == \"$EXE_NAME\" or .appname == \"$EXE_NAME\") | .appid")
        sleep 1
    done
    echo "done."
    echo "App ID is $APP_ID"
}

print_progress() {
	NUM_LINES=$1
	WIDTH=${2:-20}
	awk -v nLines=$NUM_LINES -v w=$WIDTH 'BEGIN {
		ORS=""
		linesPerDot=int(nLines/w)
        interval=int(nLines/1000)
        if(interval==0) {
			interval=1
		}
	}

	{
        if(NR<nLines && NR%interval != 0) {
            next
        }
		printf "\r["
		i=0
		for(; i<NR/linesPerDot-1 && i<w; i++){
			printf "="
		}
		if(i<w) {
			print ">"
			i++
		}
		for(; i<w; i++) {
			printf " "
		}
		printf("] %*d/%d (%02d%)", length(nLines), NR, nLines, int((NR/nLines)*100))
	}'
    echo ""
}

handle_continue() {
    continue=${continue:-"N"}
    if [ "$continue" = "n" ] || [ "$continue" = "N" ]; then echo "Aborting installation." && exit 0; fi
    if [ "$continue" != "y" ] && [ "$continue" != "Y" ]; then
        echo "Unknown option $continue" && exit 1
    fi
}

check_existing_minecraft() {
    local continue=y
    if [ -f "$MC_CONTENT" ]; then
        SKIP_MC=true
        read -p "The Minecraft Content folder already exists. Continue installation with existing Minecraft version? (y/N) " continue
    fi
    handle_continue
}

check_existing_proton() {
    EXISTING_GE_COUNT=$(ls $HOME/.steam/root/compatibilitytools.d | grep -e '^GE' -e '^GDK' | wc -l)
    local continue=y
    if [ "${EXISTING_GE_COUNT:-0}" -gt 0 ]; then
        SKIP_PROTON=true
        echo "There is at least one existing version of GE-Proton installed. It MUST be the Weather-OS GDK-Proton version, or the game will not run."
        read -p "Continue installation with existing GE-Proton version? (y/N) " continue
    fi
    handle_continue
}

check_existing_proxy_pass() {
    PROXY_PASS_DIR=$HOME/ProxyPass
    if [ -f $PROXY_PASS_DIR ]; then
        echo "The ProxyPass folder ($PROXY_PASS_DIR) already exists. Only a fresh installation will work properly."
        echo "Remove or back up the existing folder and run the installation again."
        exit 1
    fi
}

get_input() {
    read -e -p "Enter filename of the zipped Minecraft content or press enter for the default [MCWindows.zip]: " MC_ZIP_FILENAME
    MC_ZIP_FILENAME=${MC_ZIP_FILENAME:-"MCWindows.zip"}
    ZIP_FILES=$(unzip -Z1 $MC_ZIP_FILENAME)
    SEARCH_RESULTS=$(echo "$ZIP_FILES" | grep $EXE_NAME)
    if [ "$SEARCH_RESULTS" != "$EXE_NAME" ]; then
        echo "Invalid game content: couldn't find $EXE_NAME at the top level. It should contain everything inside the Content folder." && exit 1
    fi

    read -p "Enter the hostname or IP address of the destination server: " PROXY_PASS_DESTINATION_HOST
    if [ -z "$PROXY_PASS_DESTINATION_HOST" ]; then
        echo "Must provide a non-empty host/IP for the destination server." && exit 1
    fi

    check_existing_minecraft
    check_existing_proton
    check_existing_proxy_pass
}

install_minecraft() {
    if [ "$SKIP_MC" = "true" ]; then return; fi
    echo "Extracting Minecraft..."
    mkdir -p $MC_CONTENT
    NUM_FILES=$(echo "$ZIP_FILES" | wc -l)
    unzip $MC_ZIP_FILENAME -d $MC_CONTENT | print_progress $((NUM_FILES+1))
    echo "done."
}

patch_curl() {
    echo -n "Patching networking tools... "
    # this might not work because of cloudflare
    wget -q https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-curl-8.17.0-1-any.pkg.tar.zst
    if [ $? -ne 0 ]; then echo "Error downloading MinGW-cURL" && exit 1; fi
    LIBCURL_FILE_PATH="mingw64/bin/libcurl-4.dll"
    tar -xf mingw-w64-x86_64-curl-8.17.0-1-any.pkg.tar.zst $LIBCURL_FILE_PATH
    # Overwrite built-in XCurl.dll
    mv $LIBCURL_FILE_PATH $MC_CONTENT/XCurl.dll

    CERTS_DIR=$MC_DIR/etc/ssl/certs
    mkdir -p $CERTS_DIR
    wget -q https://curl.se/ca/cacert.pem
    if [ $? -ne 0 ]; then echo "Error downloading certs" && exit 1; fi
    mv cacert.pem $CERTS_DIR/ca-bundle.crt
    echo "done."
}

install_gdk_proton() {
    if [ "$SKIP_PROTON" = true ]; then return; fi
    echo "Installing GDK-Proton..."

    PROTON_RELEASE_INFO=$(curl -s https://api.github.com/repos/Weather-OS/GDK-Proton/releases/latest)
    PROTON_RELEASE_URL=$(echo "$PROTON_RELEASE_INFO" | jq -r .assets[0].browser_download_url)
    if [ $? -ne 0 ]; then echo "Couldn't find a valid release for GDK-Proton" && exit 1; fi

    echo "Downloading..."
    PROTON_RELEASE_FILENAME=$(echo "$PROTON_RELEASE_INFO" | jq -r .assets[0].name)
    wget -q --show-progress $PROTON_RELEASE_URL
    if [ $? -ne 0 ]; then echo "Error downlading GDK-Proton" && exit 1; fi

    echo -n "Extracting... "
    TAR_FILE_COUNT=$(tar -tf $PROTON_RELEASE_FILENAME | wc -l)
    tar -zxvf $PROTON_RELEASE_FILENAME -C $HOME/.steam/root/compatibilitytools.d | print_progress $TAR_FILE_COUNT
    echo "done."
}

install_java() {
    echo -n "Installing java... "
    if command -v java > /dev/null; then
        JAVA_EXE=java
        echo "already installed." && return
    fi

    JAVA_RELEASE_FULL_JSON=$(curl -s https://api.github.com/repos/adoptium/temurin25-binaries/releases/latest)
    JAVA_RELEASE_JSON=$(echo $JAVA_RELEASE_FULL_JSON | jq '.assets[] | select (.name | test("jdk_x64_linux_hotspot.*tar.gz$"))')
    JAVA_RELEASE_URL=$(echo $JAVA_RELEASE_JSON | jq -r .browser_download_url)
    JAVA_RELEASE_FILENAME=$(echo $JAVA_RELEASE_JSON | jq -r .name)
    echo -e "\nDownloading..."
    wget -q --show-progress $JAVA_RELEASE_URL
    if [ $? -ne 0 ]; then echo "Error downloading JDK" && exit 1; fi

    echo -n "Extracting... "
    JDK_DIR_NAME=$(tar -ztf $JAVA_RELEASE_FILENAME | head -1)
    JDK_DIR_NAME=${JDK_DIR_NAME%/}
    tar -zxf $JAVA_RELEASE_FILENAME -C $HOME/.local

    export JAVA_HOME=$HOME/.local/$JDK_DIR_NAME
    echo "export JAVA_HOME=$JAVA_HOME" >> $HOME/.bash_profile
    echo 'export PATH=$PATH:$JAVA_HOME/bin' >> $HOME/.bash_profile
    JAVA_EXE=$JAVA_HOME/bin/java
    echo "done."
}

install_proxy_pass() {
    echo -n "Installing ProxyPass... "
    
    wget -q https://github.com/Kas-tle/ProxyPass/releases/latest/download/ProxyPass.jar
    if [ $? -ne 0 ]; then echo "Error downloading ProxyPass" && exit 1; fi
    mkdir -p $PROXY_PASS_DIR
    mv ProxyPass.jar $PROXY_PASS_DIR/
    chmod +x wrapper.sh
    cp wrapper.sh $PROXY_PASS_DIR/
    echo "done."
}

sign_in() {
    # Run ProxyPass once to generate config and potentially log in
    cd $PROXY_PASS_DIR
    $JAVA_EXE -jar ProxyPass.jar > output.log 2>&1 &
    PP_PID=$!
    echo "Waiting for link code..."
    MS_CODE=""
    while [ -z "$MS_CODE" ]; do
        MS_CODE=$(cat output.log | sed -rn 's/.*Enter code ([A-Z0-9]{8})$/\1/p')
        sleep 1
    done

    # Copy code to clipboard
    echo "$MS_CODE" | xargs qdbus org.kde.klipper /klipper org.kde.klipper.klipper.setClipboardContents

    echo "Code is $MS_CODE"
    echo "It has been copied to your clipboard."
    echo "Now opening the browser to sign in. Paste the code that has been copied."
    echo ""
    echo "If the browser does not open, navigate to https://www.microsoft.com/link"
    echo -n "Waiting for sign-in to complete... "

    # Wait a bit before opening so the user can read what's on the screen
    sleep 2

    xdg-open https://www.microsoft.com/link
    while [ ! -f auth.json ]; do
        sleep 1
    done
    echo "done."

    kill -1 $PP_PID
}

configure_proxy_pass() {
    # Target the standard port to ensure LAN discovery
    sed -i '/proxy/,${/port\: .*/{s/port: .*/port\: 19132/; :a; n; ba}}' config.yml
    # Apply the host to the proxy config
    sed -i '/destination/,${/host\: .*/{s/host: .*/host\: '"${PROXY_PASS_DESTINATION_HOST}"'/; :a; n; ba}}' config.yml
    echo "Configuration updated."
    cd $SCRIPT_DIR
}

post_install() {
    echo "Installation complete!
In order to launch ProxyPass every time the game launches:
Go back to the game properties in Steam. Enter this text in the Launch Options box:
$PROXY_PASS_DIR/wrapper.sh %command%

Once that is complete, you're finished! The game can be launched normally through Steam in Gaming Mode.
ProxyPass will only run while the game is running.
To change which server it's pointing to, change the 'host' value under 'destination' in the config file, which is located here:
$PROXY_PASS_DIR/config.yml

Punch wood, get good!"
}

wait_for_options() {
    echo 'Next steps:
1. Fully restart Steam.
2. Go to the Steam library, right-click on Minecraft.Windows.exe, and click Properties.
3. Under Compatibility, choose the added GE-Proton version (e.g. GE-Proton10-32).
4. Run the game through Steam (desktop mode is fine).
5. Use the Steam button to move the mouse to the green Install button and click it. The game will close.'
    echo -n "Waiting for install to finish... "
    PFX_DIR="$HOME/.steam/steam/steamapps/compatdata/$APP_ID/pfx"
    APP_DATA="$PFX_DIR/drive_c/users/steamuser/AppData/Roaming"
    OPTIONS_TXT="$APP_DATA/Minecraft Bedrock/Users/Shared/games/com.mojang/minecraftpe/options.txt"
    while [ ! -f "$OPTIONS_TXT" ]; do sleep 1; done
    echo "done."
}

wait_for_app_close() {
    echo -n "Waiting for Minecraft to close... "
    MC_PROCESSES=9999
    while [ $MC_PROCESSES -ne 0 ]; do
        MC_PROCESSES=$(ps -ef | grep [M]inecraft.Windows.exe | wc -l)
        sleep 1
    done
    echo "done."
}

modify_options() {
    sed -i 's/do_not_show_multiplayer_online_safety_warning:0/do_not_show_multiplayer_online_safety:1/g' "$OPTIONS_TXT"
}

get_input
install_minecraft
patch_curl
install_gdk_proton
install_java
install_proxy_pass
sign_in
configure_proxy_pass
wait_for_app_id
wait_for_options
wait_for_app_close
modify_options
post_install
