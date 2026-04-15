#!/bin/bash
SCRIPT_DIR=$PWD

SEARCH_RESULTS=$(unzip -Z1 MCWindows.zip | grep Minecraft.Windows.exe)
if [ "$SEARCH_RESULTS" != "Minecraft.Windows.exe" ]; then
    echo "Invalid game contents: couldn't find Minecraft.Windows.exe at the top level" && exit 1
fi

MC_DIR=$HOME/Minecraft
MC_CONTENTS=$MC_DIR/Contents
mkdir -p $MC_CONTENTS
unzip MCWindows.zip -d $MC_CONTENTS

# this might not work because of cloudflare
wget https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-curl-8.17.0-1-any.pkg.tar.zst
tar -xf mingw-w64-x86_64-curl-8.17.0-1-any.pkg.tar.zst mingw64/bin/libcurl-4.dll
# Overwrite built-in XCurl.dll
mv libcurl-4.dll $MC_CONTENTS/XCurl.dll

CERTS_DIR=$MC_DIR/etc/ssl/certs
mkdir -p $CERTS_DIR
wget https://curl.se/ca/cacert.pem
mv cacert.pem $CERTS_DIR/ca-bundle.crt

PROTON_RELEASE_INFO=$(curl -s https://api.github.com/repos/Weather-OS/GDK-Proton/releases/latest)
PROTON_RELEASE_URL=$(echo "$PROTON_RELEASE_INFO" | jq -r .assets[0].browser_download_url)
PROTON_RELEASE_FILENAME=$(echo "$PROTON_RELEASE_INFO" | jq -r .assets[0].name)
wget $PROTON_RELEASE_URL
tar -zxf $PROTON_RELEASE_FILENAME -C $HOME/.steam/root/compatibilitytools.d

# Need to restart Steam

JAVA_RELEASE_FULL_JSON=$(curl -s https://api.github.com/repos/adoptium/temurin25-binaries/releases/latest)
JAVA_RELEASE_JSON=$(echo $JAVA_RELEASE_FULL_JSON | jq '.assets[] | select (.name | test("jdk_x64_linux_hotspot.*tar.gz$"))')
JAVA_RELEASE_URL=$(echo $JAVA_RELEASE_JSON | jq -r .browser_download_url)
JAVA_RELEASE_FILENAME=$(echo $JAVA_RELEASE_JSON | jq -r .name)
wget $JAVA_RELEASE_URL
JDK_DIR_NAME=$(tar -ztf $JAVA_RELEASE_FILENAME | head -1)
tar -zxf $JAVA_RELEASE_FILENAME -C $HOME/.local
JAVA_HOME=$HOME/.local/$JDK_DIR_NAME
echo "JAVA_HOME=$HOME/.local/$JDK_DIR_NAME" >> $HOME/.bash_profile
echo 'PATH=$PATH:$JAVA_HOME/bin' >> $HOME/.bash_profile
JAVA_EXE=$JAVA_HOME/bin/java

PROXY_PASS_DIR=$HOME/ProxyPass
wget https://github.com/Kas-tle/ProxyPass/releases/latest/ProxyPass.jar
mkdir -p $PROXY_PASS_DIR
mv ProxyPass.jar $PROXY_PASS_DIR/
mv wrapper.sh $PROXY_PASS_DIR/

# Run ProxyPass once to generate config (and potentially log in?)
cd $PROXY_PASS_DIR
$JAVA_EXE -jar ProxyPass.jar > output.log 2>&1 &
PP_PID=$!
echo "Waiting for link code..."
MS_CODE_LINE=""
while [ -z "$MS_CODE_LINE" ]; do
    MS_CODE_LINE=$(cat output.log | grep "TODO-FIND-SEARCH-STRING")
    sleep 1
done

echo $MS_CODE_LINE
echo "Waiting for link to complete..."
while [ ! -f auth.json ]; do
    sleep 1
done

kill -1 $PP_PID

# Apply the host to the proxy config
PROXY_PASS_DESTINATION_HOST=192.168.1.100 # example
sed -i '/destination/,${/host\: .*/{s/host: .*/host\: '"${PROXY_PASS_DESTINATION_HOST}"'/; :a; n; ba}}' config.yml

# Restart steam, tick the box for "Force the use of a specific Steam Play compatibility tool"
# Set the launch options to: $HOME/ProxyPass/wrapper.sh %command%
