# Multica Android build

基于固定版本的 [Multica](https://github.com/multica-ai/multica) 源码构建可直接安装、无需 Metro 的 Android APK。所有上游修改维护在 `patches/`，构建前按文件名顺序 `git apply`；不提交生成的 Android 工程。

## GitHub Actions

把本仓库推送到 GitHub 的 `main` 或 `master` 后，push、PR 和手动运行 `Android APK` workflow 都会构建。完成后在 Actions 页面下载 `multica-android-<run_number>` artifact，里面包含 APK、SHA-256 和构建配置记录。

在仓库 Settings → Secrets and variables → Actions → Variables 设置：

| Variable | 默认值 | 用途 |
| --- | --- | --- |
| `MULTICA_API_URL` | `https://api.multica.ai` | API 基础地址，不加 `/api` |
| `MULTICA_SITE_URL` | `https://multica.ai` | 分享、复制和打开网页使用的站点地址 |
| `ANDROID_PACKAGE` | `ai.multica.mobile.android` | Android application ID |

手动运行时可以覆盖这三个值。地址必须是 HTTPS，不包含账号密码、查询参数或 fragment；结尾斜杠会被去掉。API 和站点地址可以不同，都会编译进 APK，**不是秘密，也不能在安装后修改**；改地址后需重新构建。这里的 site URL 对应上游变量 `EXPO_PUBLIC_WEB_URL`。设置 `EXPO_NO_DOTENV=1`，避免上游 `.env.production` 覆盖定制配置。

上游当前为公开仓库，无需额外 token。若改为私有 fork，设置只具备该仓库读取权限的 `UPSTREAM_READ_TOKEN` secret；fork PR 无法读取这个 secret。

生成的是 **release 模式、Expo 默认 debug key 签名的侧载 APK**，不是商店发行包。支持 Android 7.0（API 24）及以上，包含 arm64-v8a 和 x86_64 架构。独立 application ID 避免覆盖官方客户端；上架或正式分发前应配置自有长期签名密钥，不要用此默认签名。versionCode 使用 Actions run number；跨 workflow/仓库迁移时注意保持递增。

## 本地构建（支持 headless Linux）

需要 Node.js 22、pnpm 10.28.2、JDK 17、Android SDK 命令行工具。无需 Android Studio、桌面会话或模拟器。按 [Android 命令行工具说明](https://developer.android.com/tools/sdkmanager) 安装 SDK，并设置：

```bash
export JAVA_HOME=/path/to/jdk17
export ANDROID_HOME="$HOME/.local/share/android-sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/19.0/bin:$ANDROID_HOME/platform-tools:$PATH"
sdkmanager --licenses
sdkmanager 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0'
```

Gradle 会根据固定版本的上游配置安装所需 NDK/CMake；首次构建需要网络和足够的磁盘空间。

从本仓库根目录执行：

```bash
source upstream.env
git clone "https://github.com/$UPSTREAM_REPOSITORY.git" source
git -C source checkout --detach "$UPSTREAM_REF"
scripts/apply-patches.sh "$PWD/source"
(cd source && pnpm install --frozen-lockfile --filter @multica/mobile...)
EXPO_PUBLIC_API_URL=https://api.example.com \
EXPO_PUBLIC_WEB_URL=https://multica.example.com \
ANDROID_VERSION_CODE=1 \
scripts/build-android.sh "$PWD/source"
```

产物在 `artifacts/`。已经打过补丁的 checkout 可直接重新构建，不要再次运行 `apply-patches.sh`。请在专用、无本地改动的 checkout 应用补丁；应用失败时脚本立即停止，并可能保留已成功应用的前序补丁。

使用 `adb install -r artifacts/multica.apk` 安装到连接的设备。构建可以在无图形界面的机器完成；菜单交互、登录和分享仍应在真机验收。

## 补丁与升级

`upstream.env` 固定上游 commit，防止上游更新静默破坏构建：

- `0001-android-config-and-endpoints.patch`：Android 包名/versionCode；统一 API、WebSocket、附件和站点链接的 URL 读取、校验与尾斜杠处理，并增加 URL 测试。
- `0002-android-action-menus-and-icons.patch`：Android 多选项菜单（含取消、返回键、禁用项及危险操作样式），保留 iOS 原生菜单；把导航中的 SF Symbols 映射到 Android 可显示的 Material Icons。

升级时在新的独立 checkout 上依次尝试补丁，解决冲突并重新导出 diff，然后更新 `UPSTREAM_REF`。不要直接忽略失败的补丁。CI 执行移动端 typecheck、lint、test 后再生成 Android 工程并运行 Gradle `assembleRelease`。

构建流程参考 [Expo 本地 release 构建](https://docs.expo.dev/guides/local-app-production/)。Android 菜单使用可滚动 Modal，因为 [React Native Alert](https://reactnative.dev/docs/alert) 在 Android 上最多支持三个按钮，无法容纳评论的全部操作。
