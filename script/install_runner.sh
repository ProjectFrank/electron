#!/bin/bash
set -eo pipefail

platform=darwin/amd64
prefix=/opt/circleci
sudo mkdir -p "$prefix/workdir"
base_url="https://circleci-binary-releases.s3.amazonaws.com/circleci-launch-agent"
echo "Determining latest version of CircleCI Launch Agent"
agent_version=$(curl "$base_url/release.txt")
echo "Using CircleCI Launch Agent version $agent_version"
echo "Downloading and verifying CircleCI Launch Agent Binary"
curl -sSL "$base_url/$agent_version/checksums.txt" -o checksums.txt
file="$(grep -F "$platform" checksums.txt | cut -d ' ' -f 2 | sed 's/^.//')"
mkdir -p "$platform"
echo "Downloading CircleCI Launch Agent: $file"
curl --compressed -L "$base_url/$agent_version/$file" -o "$file"
echo "Verifying CircleCI Launch Agent download"
grep "$file" checksums.txt | shasum -a 256 --check && chmod +x "$file"; sudo cp "$file" "$prefix/circleci-launch-agent" || echo "Invalid checksum for CircleCI Launch Agent, please try download again"

runner_token="${1}"

cat > launch-agent-config.yaml <<EOF
api:
    auth_token: $runner_token
runner:
    name: bob
    command_prefix: ["sudo", "-niHu", "administrator", "--"]
    working_directory: /tmp/%s
    cleanup_working_directory: true
logging:
    file: /Library/Logs/com.circleci.runner.log
EOF

sudo mkdir -p '/Library/Preferences/com.circleci.runner'
sudo cp 'launch-agent-config.yaml' '/Library/Preferences/com.circleci.runner/launch-agent-config.yaml'

sudo tee /Library/LaunchDaemons/com.circleci.runner.plist > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.circleci.runner</string>
        <key>Program</key>
        <string>/opt/circleci/circleci-launch-agent</string>
        <key>ProgramArguments</key>
        <array>
            <string>circleci-launch-agent</string>
            <string>--config</string>
            <string>/Library/Preferences/com.circleci.runner/launch-agent-config.yaml</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <!-- The agent needs to run at all times -->
        <key>KeepAlive</key>
        <true/>
        <!-- This prevents macOS from limiting the resource usage of the agent -->
        <key>ProcessType</key>
        <string>Interactive</string>
        <!-- Increase the frequency of restarting the agent on failure, or post-update -->
        <key>ThrottleInterval</key>
        <integer>3</integer>
        <!-- Wait for 10 minutes for the agent to shut down (the agent itself waits for tasks to complete) -->
        <key>ExitTimeOut</key>
        <integer>600</integer>
        <!-- The agent uses its own logging and rotation to file -->
        <key>StandardOutPath</key>
        <string>/dev/null</string>
        <key>StandardErrorPath</key>
        <string>/dev/null</string>
    </dict>
</plist>
EOF
sudo launchctl unload '/Library/LaunchDaemons/com.circleci.runner.plist'
sudo launchctl load '/Library/LaunchDaemons/com.circleci.runner.plist'
