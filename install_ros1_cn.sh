#!/usr/bin/env bash
# 在 Ubuntu 20.04 上安装 ROS 1 Noetic（使用中科大镜像）。
# 用法：bash install_ros1_cn.sh [desktop-full|desktop|ros-base] [--skip-extras]

set -Eeuo pipefail

readonly ROS_DISTRO="noetic"
readonly MIRROR_BASE="https://mirrors.ustc.edu.cn/ros/ubuntu"
readonly KEYRING="/usr/share/keyrings/ros-archive-keyring.gpg"
readonly SOURCE_FILE="/etc/apt/sources.list.d/ros1.list"
readonly ROS_SETUP="/opt/ros/${ROS_DISTRO}/setup.bash"

die() { echo "错误：$*" >&2; exit 1; }
note() { echo "==> $*"; }

package_variant="desktop-full"
install_extras=true
for argument in "$@"; do
  case "$argument" in
    desktop-full|desktop|ros-base) package_variant="$argument" ;;
    --skip-extras) install_extras=false ;;
    -h|--help)
      sed -n '1,3p' "$0"
      exit 0
      ;;
    *) die "未知参数：$argument" ;;
  esac
done
case "$package_variant" in
  desktop-full) ros_package="ros-${ROS_DISTRO}-desktop-full" ;;
  desktop)      ros_package="ros-${ROS_DISTRO}-desktop" ;;
  ros-base)     ros_package="ros-${ROS_DISTRO}-ros-base" ;;
  *) die "安装类型仅支持 desktop-full、desktop 或 ros-base" ;;
esac

# 来自入门、移动机器人仿真和课程实验常用的官方 Noetic 二进制包。
# desktop-full 本身含有其中一部分；apt 会自动跳过已经安装的包。
readonly -a USEFUL_ROS_PACKAGES=(
  ros-noetic-turtlesim
  ros-noetic-rqt
  ros-noetic-rqt-graph
  ros-noetic-rqt-tf-tree
  ros-noetic-tf2-tools
  ros-noetic-xacro
  ros-noetic-urdf-tutorial
  ros-noetic-joint-state-publisher-gui
  ros-noetic-robot-state-publisher
  ros-noetic-teleop-twist-keyboard
  ros-noetic-joy
  ros-noetic-gazebo-ros-control
  ros-noetic-ros-control
  ros-noetic-ros-controllers
  ros-noetic-turtlebot3
  ros-noetic-turtlebot3-simulations
  ros-noetic-turtlebot3-navigation
  ros-noetic-navigation
  ros-noetic-map-server
  ros-noetic-slam-gmapping
  ros-noetic-amcl
  ros-noetic-robot-localization
  ros-noetic-image-transport
  ros-noetic-cv-bridge
  ros-noetic-vision-opencv
  ros-noetic-pcl-ros
  ros-noetic-usb-cam
)

[[ "${EUID}" -ne 0 ]] || die "请用普通用户执行；脚本会在需要时调用 sudo。"
command -v sudo >/dev/null || die "未找到 sudo。"

[[ -r /etc/os-release ]] || die "无法读取 /etc/os-release。"
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "仅支持 Ubuntu；当前系统：${PRETTY_NAME:-未知}"
[[ "${VERSION_ID:-}" == "20.04" && "${VERSION_CODENAME:-}" == "focal" ]] || \
  die "ROS 1 Noetic 的原生安装仅支持 Ubuntu 20.04 (focal)；当前系统：${PRETTY_NAME:-未知}"

note "安装 ROS 1 ${ROS_DISTRO}（${ros_package}），软件源：中科大镜像"
note "安装基础工具"
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  curl ca-certificates gnupg lsb-release xdg-user-dirs \
  tmux git vim nano htop tree wget unzip zip net-tools iputils-ping \
  openssh-client python3-pip python3-catkin-tools python3-vcstool

note "配置 ROS 软件源与签名密钥"
curl -fsSL --retry 3 --connect-timeout 10 \
  https://mirrors.ustc.edu.cn/rosdistro/ros.key |
  sudo gpg --dearmor --yes -o "$KEYRING"
printf 'deb [arch=%s signed-by=%s] %s %s main\n' \
  "$(dpkg --print-architecture)" "$KEYRING" "$MIRROR_BASE" "$VERSION_CODENAME" |
  sudo tee "$SOURCE_FILE" >/dev/null

note "更新索引并安装 ROS（这一步可能需要几分钟）"
sudo apt-get update
sudo apt-get install -y "$ros_package" python3-rosdep python3-rosinstall \
  python3-rosinstall-generator python3-wstool build-essential
if "$install_extras"; then
  note "安装常用开发、仿真、导航与视觉工具包"
  sudo apt-get install -y "${USEFUL_ROS_PACKAGES[@]}"
fi

note "初始化 rosdep"
if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
  sudo rosdep init
fi
# rosdep 的索引来自 rosdistro；失败不影响 ROS 本体使用，但依赖解析会不可用。
if ! rosdep update; then
  echo "警告：rosdep update 失败。ROS 已安装；网络恢复后可单独执行：rosdep update" >&2
fi

if ! grep -qsF "$ROS_SETUP" "$HOME/.bashrc" 2>/dev/null; then
  {
    echo
    echo "# ROS 1 Noetic"
    echo "source $ROS_SETUP"
  } >> "$HOME/.bashrc"
fi

note "创建默认 catkin 工作空间"
workspace="$HOME/catkin_ws"
mkdir -p "$workspace/src"
if [[ ! -f "$workspace/src/CMakeLists.txt" ]]; then
  (
    source "$ROS_SETUP"
    cd "$workspace"
    catkin_make
  )
fi
if [[ -f "$workspace/devel/setup.bash" ]] && ! grep -qsF "$workspace/devel/setup.bash" "$HOME/.bashrc"; then
  echo "source $workspace/devel/setup.bash" >> "$HOME/.bashrc"
fi
if "$install_extras" && ! grep -qs '^export TURTLEBOT3_MODEL=' "$HOME/.bashrc" 2>/dev/null; then
  {
    echo
    echo "# TurtleBot3 仿真默认机器人型号"
    echo "export TURTLEBOT3_MODEL=burger"
  } >> "$HOME/.bashrc"
fi

note "部署 rostmux 四分屏命令"
mkdir -p "$HOME/.local/bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  'start_dir="${ROS_WORKSPACE:-$HOME/catkin_ws}"' \
  'mkdir -p "$start_dir"' \
  'session_name="ros1-$(date +%s)-$RANDOM"' \
  'tmux new-session -d -s "$session_name" -c "$start_dir" bash -i' \
  'tmux split-window -h -t "$session_name":0 -c "$start_dir" bash -i' \
  'tmux split-window -v -t "$session_name":0.0 -c "$start_dir" bash -i' \
  'tmux split-window -v -t "$session_name":0.2 -c "$start_dir" bash -i' \
  'tmux select-layout -t "$session_name":0 tiled' \
  'exec tmux attach-session -t "$session_name"' > "$HOME/.local/bin/rostmux"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  "if command -v ptyxis >/dev/null 2>&1; then exec ptyxis --new-window --title='ROS 1 分屏' -- bash -lc 'exec rostmux'; fi" \
  "if command -v kgx >/dev/null 2>&1; then exec kgx --title='ROS 1 分屏' -- bash -lc 'exec rostmux'; fi" \
  "if command -v gnome-terminal >/dev/null 2>&1; then exec gnome-terminal --title='ROS 1 分屏' -- bash -lc 'exec rostmux'; fi" \
  "if command -v konsole >/dev/null 2>&1; then exec konsole --new-tab -p tabtitle='ROS 1 分屏' -e bash -lc 'exec rostmux'; fi" \
  "if command -v x-terminal-emulator >/dev/null 2>&1; then exec x-terminal-emulator -e bash -lc 'exec rostmux'; fi" \
  'echo "未找到受支持的图形终端，请在已有终端中执行 rostmux。" >&2' \
  'exit 1' > "$HOME/.local/bin/launch-rostmux"
chmod 0755 "$HOME/.local/bin/rostmux" "$HOME/.local/bin/launch-rostmux"
if ! grep -qsF '$HOME/.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

note "创建 ROS 1 桌面快捷方式"
desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
if [[ -z "$desktop_dir" || "$desktop_dir" == "$HOME" ]]; then
  desktop_dir="$HOME/Desktop"
fi
mkdir -p "$desktop_dir"
desktop_file="$desktop_dir/ROS1.desktop"
printf '%s\n' \
  '[Desktop Entry]' \
  'Version=1.0' \
  'Type=Application' \
  'Name=ROS1' \
  'Comment=打开 ROS 1 Noetic 四分屏开发终端' \
  "Exec=$HOME/.local/bin/launch-rostmux" \
  'Icon=utilities-terminal' \
  'Terminal=false' \
  'Categories=Development;Utility;' \
  'StartupNotify=true' > "$desktop_file"
chmod 0755 "$desktop_file"
if command -v gio >/dev/null 2>&1; then
  gio set "$desktop_file" metadata::trusted true 2>/dev/null || true
fi

if command -v code >/dev/null 2>&1; then
  note "安装 VS Code 的 ROS 开发扩展"
  readonly -a VSCODE_EXTENSIONS=(
    ms-iot.vscode-ros
    ms-vscode.cpptools
    ms-python.python
    ms-vscode.cmake-tools
    redhat.vscode-xml
    redhat.vscode-yaml
  )
  for extension in "${VSCODE_EXTENSIONS[@]}"; do
    code --install-extension "$extension" --force || \
      echo "警告：VS Code 扩展安装失败：$extension" >&2
  done
fi

note "安装完成"
echo "ROS 发行版：$(source "$ROS_SETUP" && rosversion -d)"
echo "请执行：source ~/.bashrc"
echo "验证命令：roscore"
echo "四分屏命令：rostmux"
echo "桌面快捷方式：$desktop_file"
if "$install_extras"; then
  echo "仿真示例：roslaunch turtlebot3_gazebo turtlebot3_world.launch"
fi
