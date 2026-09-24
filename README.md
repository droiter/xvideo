# xVideo · 家庭视频库

基于 **Flutter** 的家庭视频库 App，面向 **平板与手机**，一套代码同时适配 Android / iOS。

![flutter](https://img.shields.io/badge/Flutter-3.x-blue)
![license](https://img.shields.io/badge/license-MIT-lightgrey)

---

## 一、项目简介

xVideo 是从 [xEdu](https://github.com/droiter/xedu) 里拆出来的**独立看视频 App**：
只保留「看视频」与「我的」两块，去掉课程、看图找规律、看图问答与学习进度。

- **底部两格选项卡**：看视频 / 我的
- **看视频**：展示「我的」里建好的视频分类，点分类进去看视频列表，点视频即全屏播放
- **视频管理**：建 / 改名 / 删分类，往分类里加视频（粘贴 http(s) 链接，或从本机选文件）
- **免登录可用**：不注册也能直接看视频，登录入口只在「我的」页里

> **免登录是刻意的**：引导页看完直接进主界面，登录态不拦任何页面。
> 账号只是本机的一份假认证，**不隔离任何数据** —— 视频库本来就是全机一份
> （家长在平板上加片，孩子账号照样看），所以不登录没有任何功能损失。
> 登录页是从「我的」推上来的普通路由，注册 / 登录成功后返回「我的」。

**与 xEdu 的关系**：xVideo 与 xEdu 是**两份独立代码**，目录结构刻意保持一致
（`lib/{core,data,state,shared,features/{video,auth,onboarding,profile,shell}}`），
但改一边不会同步到另一边。

## 二、快速开始

本仓库已包含可直接构建的 `android/` 平台工程（含两条原生通道，见下文），
**不需要**再跑 `flutter create`。

```bash
flutter pub get
flutter run        # 选择连接的手机 / 平板 / 模拟器

flutter analyze    # 静态检查
flutter test       # 单元与 widget 测试
```

**打包安卓 APK**（产物 `build/app/outputs/flutter-apk/app-release.apk`）：

```bash
# 通用包（arm64-v8a + armeabi-v7a + x86_64），约 54 MB
flutter build apk --release

# 只出 arm64，体积约 20 MB（绝大多数平板 / 手机都是这个架构）
flutter build apk --release --target-platform android-arm64
```

说明：

- 生成的 release APK 默认用**调试签名**，直接侧载安装即可；要上应用商店
  再配置正式 keystore（`android/app/build.gradle.kts` 的 signingConfigs）。
- 应用图标目前为 Flutter 默认图标；如需自定义，替换
  `android/app/src/main/res/mipmap-*/ic_launcher.png`。
- `applicationId` 是 **`com.xvideo.app`**，与 xEdu 不同，两个 App 可以装在同一台机器上共存。

## 三、功能清单

| 模块 | 说明 |
| --- | --- |
| 引导页 | 3 页轮播，可跳过，状态持久化；看完直接进主界面（**不强制登录**） |
| 看视频 | 宫格分类卡；空态给「去添加视频」直接跳到「我的」；分类下视频以大方块网格铺开，手机 2 列 / 平板最多 4 列 |
| 视频播放 | 黑底全屏播放 + 进度条拖动；放完自动退回列表；**播放中触摸画面不会暂停**（回到控制条上的按键才暂停）；**返回键完全不拦** |
| 视频缩略图 | 本机视频抽一帧（取片长 1/10 处，避开片头黑场）缓存成图；链接视频用渐变占位图 |
| 视频管理 | 「我的 → 我的视频」：新建 / 重命名 / 删除分类；加视频二选一——粘链接 或 选本机文件 |
| 本机文件 | 选中的文件**复制进 App 私有目录**再记路径（选择器给的是缓存路径，系统一清就播不了）；删视频 / 删分类会一起清掉副本与缩略图 |
| 账号 | 本地注册 / 登录 / 退出，「我的」页里的入口；未登录时顶部是「未登录 · 点这里登录或注册」卡片 |
| 深色模式 | 「我的」页开关，手动选择，持久化 |
| 自适应 | 手机（窄屏两列）与平板（多列宫格）两套布局 |

> xEdu 那套 6 格选项卡、课程 / 进度 / 看图找规律 / 看图问答**都没有**搬过来；
> 「我的」页里的「学习提醒」「朗读语速」也没搬（分别属于课程提醒与问答朗读，这里用不上）。

## 四、项目结构

```
lib/
├─ main.dart                       # 入口：注入 SharedPreferences 后启动
├─ app.dart                        # MaterialApp + 主题
├─ core/
│  ├─ constants.dart               # 应用名、SharedPreferences 键、选项卡下标、封面调色板
│  └─ theme.dart                   # 亮 / 暗主题
├─ data/
│  └─ models.dart                  # User / AuthState
├─ state/                          # Riverpod providers
│  ├─ prefs.dart  providers.dart
│  ├─ auth.dart                    # 本地账号（假认证）
│  ├─ onboarding.dart              # 引导页是否看过
│  ├─ theme_controller.dart        # 深色模式
│  └─ video_library.dart           # 视频库（分类 + 视频），全机共用一份
├─ shared/widgets/                 # 空态提示、封面渐变
└─ features/
   ├─ shell/main_shell.dart        # 底部两格手写选项卡
   ├─ video/
   │  ├─ video_library_screen.dart # 「看视频」分类宫格
   │  ├─ video_category_screen.dart# 分类下的视频方块网格
   │  ├─ video_player_screen.dart  # 全屏播放页
   │  ├─ video_manage_screen.dart  # 「我的视频」管理页
   │  ├─ video_import.dart         # 选本机文件 + 复制进私有目录 + 问系统要真文件名
   │  └─ video_thumbnail.dart      # 缩略图抽取与缓存
   ├─ auth/login_screen.dart       # 登录 / 注册（从「我的」推上来）
   ├─ onboarding/onboarding_screen.dart
   └─ profile/profile_screen.dart  # 账号卡 / 我的视频 / 深色模式 / 关于 / 退出登录
```

### 原生侧（`android/app/src/main/kotlin/com/xvideo/app/MainActivity.kt`）

两条 MethodChannel：

| 通道 | 方法 | 用途 |
| --- | --- | --- |
| `xvideo/picker` | `displayName` | `file_picker` 只问 `OpenableColumns.DISPLAY_NAME`，相册给的 `content://` 地址问不到名字时会退回一串编号；这里依次再问 `display_name` / `_display_name` / `title`，最后拿 `_ID` 去 MediaStore 查，拿到真文件名 |
| `xvideo/video` | `thumbnail` | `MediaMetadataRetriever` 抽帧（取片长 1/10 处）→ 缩放 → JPEG 返回字节。用单线程 Executor 串行解码，避免几十个视频一起解把平板拖死 |

## 五、数据说明（接入后端前）

当前为**纯本地演示**，没有服务端：

| 内容 | 位置 |
| --- | --- |
| 账号 | SharedPreferences（`xvideo_users` / `xvideo_session`） |
| 视频库（分类 + 视频） | SharedPreferences（`xvideo_video_lib`），**全机共用一份** |
| 深色模式 / 引导页状态 | SharedPreferences（`xvideo_dark` / `xvideo_seen_onboarding`） |
| 本机视频文件副本 | App 私有目录 `xvideo_videos/<时间戳>_<文件名>`（卸载才清除，不会被系统当缓存清掉） |
| 视频缩略图 | App 私有目录 `xvideo_thumbs/<videoId>.jpg` |

**主要扩展点**

- `lib/state/auth.dart`：把假认证换成真实登录接口
- `lib/state/video_library.dart`：把 SharedPreferences 换成后端视频库 API
- 分类封面色：`lib/core/constants.dart` 的 `kCoverPalette`

## 六、测试

```bash
flutter test        # 60 例，全过
```

- `app_smoke_test.dart`：免登录进主界面、未登录「我的」有登录入口、注册后退回并显示账号、
  登录页点返回不改登录态、退出登录后仍在主界面、界面上没有课程 / 答题字样、深色模式落盘
- `video_library_test.dart`：视频库状态与持久化、管理页、看视频、播放页、视频名预填（含
  问不到名字时自己再问系统一次）、本机视频指纹、分类下视频方块网格的列数与尺寸
- `video_player_screen_test.dart`：用假播放器顶上平台通道，验证「放完自动退回」「播放中
  摸画面不暂停」「点正中播放圆钮也不会被吃掉点击」
- `video_thumbnail_test.dart`：缩略图缓存（抽取 / 复用 / 并发去重 / 失败不重试 / 链接不抽帧 /
  删视频清文件 / 通道未接不炸）
