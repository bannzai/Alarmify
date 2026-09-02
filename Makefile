XCODEPROJ := Alarmify.xcodeproj
# Simulator 向けは ad-hoc 署名する。CODE_SIGNING_ALLOWED=NO では entitlements が付かず、
# Keychain の読み書きが errSecMissingEntitlement (-34018) で失敗する (証明書は不要)
SIM_CODE_SIGN := CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
SCHEME := Alarmify
CONFIGURATION := Debug
DERIVED_DATA := tmp/DerivedData
APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/Alarmify.app
IOS_APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphoneos/Alarmify.app
BUNDLE_ID := com.bannzai.Alarmify
# Firebase Functions のデプロイ先。.firebaserc の alias で指定する (取り違え防止のため常に明示する)
FIREBASE_ALIAS ?= prod
# firebase-tools は .github/workflows/functions-deploy.yml と同じバージョンに固定する (CLI 更新で挙動が変わらないように)
FIREBASE_TOOLS_VERSION := 15.28.2
# デプロイ対象を絞る場合の関数名 (カンマ区切り。例: FUNCTIONS=v1-alarms-create,v1-alarms-cancel)。空なら functions 全体。
# firebase の部分デプロイは対象ごとに functions: の接頭辞が要るため、recipe 側で付け直す
FUNCTIONS ?=
SIMULATOR_UDID ?= $(shell SCRIPT_QUIET=1 sim-boot | sed -n 's/^DEVICE_UDID=//p' | tail -n 1)
DESTINATION ?= platform=iOS Simulator,id=$(SIMULATOR_UDID)

.PHONY: build-ios device install-device ios test clean deploy-functions

# Simulator 向けビルド。generic destination なら simulator の起動なしでビルドできる
build-ios:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) -destination 'generic/platform=iOS Simulator' $(SIM_CODE_SIGN) build

# 実機向けビルド。code signing が必要なため、provisioning profile の自動生成とこの Mac へのデバイス登録を CLI から行えるようにする
device:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) -destination 'generic/platform=iOS' -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

# 実機ビルドを実機にインストールする。インストール先の解決順: DEVICE 変数 (名前 / UDID) > 環境変数 IOS_DEVICE_UDID > devicectl の JSON から接続中デバイスを自動解決
install-device: device
	@mkdir -p tmp; \
	device="$(DEVICE)"; \
	[ -n "$$device" ] || device="$(IOS_DEVICE_UDID)"; \
	if [ -z "$$device" ]; then \
		xcrun devicectl list devices --json-output tmp/devices.json > /dev/null; \
		device=$$(jq -r '[.result.devices[] | select(.connectionProperties.tunnelState == "connected")][0].identifier // empty' tmp/devices.json); \
	fi; \
	[ -n "$$device" ] || { echo "Error: 実機が見つかりません (IOS_DEVICE_UDID を export するか DEVICE=<名前|UDID> で指定してください)" >&2; exit 1; }; \
	xcrun devicectl device install app --device "$$device" "$(IOS_APP)"; \
	xcrun devicectl device process launch --device "$$device" $(BUNDLE_ID)

# Simulator 向けビルドを sim-boot で起動した simulator にインストールして起動する
ios: build-ios
	@set -e; \
	simulator_udid="$(SIMULATOR_UDID)"; \
	[ -n "$$simulator_udid" ] || { echo "Error: sim-boot でSimulatorを解決できません (sim-bootがPATHにあるか確認するか、SIMULATOR_UDID=<UDID>を指定してください)" >&2; exit 1; }; \
	xcrun simctl install "$$simulator_udid" $(APP); \
	xcrun simctl launch "$$simulator_udid" $(BUNDLE_ID)

test:
	@set -e; \
	destination="$(DESTINATION)"; \
	[ -n "$$destination" ] && [ "$$destination" != "platform=iOS Simulator,id=" ] || { echo "Error: sim-boot でSimulatorを解決できません (sim-bootがPATHにあるか確認するか、DESTINATION='<destination>'またはSIMULATOR_UDID=<UDID>を指定してください)" >&2; exit 1; }; \
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA) -destination "$$destination" $(SIM_CODE_SIGN) test

clean:
	rm -rf $(DERIVED_DATA)

# Functions を .firebaserc の alias で指定した Firebase プロジェクトへデプロイする。
# GitHub Actions の functions-deploy.yml と同じコマンドで、ローカルからも同じ経路でデプロイできるようにする
deploy-functions:
	@set -e; \
	alias_name="$(FIREBASE_ALIAS)"; \
	[ -n "$$alias_name" ] || { echo "Error: FIREBASE_ALIAS が空です (例: make deploy-functions FIREBASE_ALIAS=prod)" >&2; exit 1; }; \
	project_id=$$(jq -r --arg alias "$$alias_name" '.projects[$$alias] // empty' .firebaserc); \
	[ -n "$$project_id" ] || { echo "Error: .firebaserc に alias '$$alias_name' がありません" >&2; exit 1; }; \
	[ -d functions ] || { echo "Error: functions/ がありません (バックエンドの雛形は issue #2 で追加する)" >&2; exit 1; }; \
	if [ -n "$(FUNCTIONS)" ]; then \
		target=$$(printf '%s' "$(FUNCTIONS)" | awk -F',' '{for (i = 1; i <= NF; i++) { gsub(/^[ \t]+|[ \t]+$$/, "", $$i); if ($$i != "") printf "%sfunctions:%s", (n++ ? "," : ""), $$i }}'); \
		[ -n "$$target" ] || { echo "Error: FUNCTIONS の指定が空です" >&2; exit 1; }; \
	else target="functions"; fi; \
	echo "デプロイ先: alias=$$alias_name project=$$project_id target=$$target"; \
	npx --yes firebase-tools@$(FIREBASE_TOOLS_VERSION) deploy --only "$$target" --project "$$alias_name" --non-interactive
