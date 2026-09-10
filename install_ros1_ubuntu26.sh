#!/usr/bin/env bash
# Ubuntu 26.04 上的 ROS 1 Noetic 完整容器化部署（含 tmux 与桌面快捷方式）
# 用法：./install_ros1_ubuntu26.sh [--repair-shortcut|--doctor]
set -Eeuo pipefail

readonly CONTAINER_NAME="${ROS1_CONTAINER_NAME:-ros1_course}"
readonly TARGET_IMAGE="${ROS1_IMAGE:-osrf/ros:noetic-desktop-full}"
PROJECT_DIR="${ROS1_HOME:-$HOME/ROS1}"
readonly ROS_MIRROR="https://mirrors.ustc.edu.cn/ros/ubuntu"

note() { echo "==> $*"; }
die() { echo "错误：$*" >&2; exit 1; }
CURRENT_STAGE="启动"
stage() { CURRENT_STAGE="$*"; note "$*"; }
on_error() {
  local exit_code=$?
  echo >&2
  echo "部署失败：阶段=$CURRENT_STAGE，行号=${BASH_LINENO[0]}，退出码=$exit_code" >&2
  echo "修复网络或软件源后可直接重新运行，已完成的步骤会自动跳过。" >&2
  echo "完整日志：${LOG_FILE:-尚未建立}" >&2
  exit "$exit_code"
}
trap on_error ERR

show_doctor() {
  echo "系统：${PRETTY_NAME:-未知}"
  echo "架构：$(uname -m)"
  echo "可用磁盘：$(df -h "$HOME" | awk 'NR==2 {print $4}')"
  for doctor_cmd in sudo curl docker tmux xdg-user-dir gio gnome-extensions; do
    if command -v "$doctor_cmd" >/dev/null 2>&1; then
      echo "[OK] $doctor_cmd: $(command -v "$doctor_cmd")"
    else
      echo "[缺少] $doctor_cmd"
    fi
  done
  if command -v docker >/dev/null 2>&1; then
    docker info >/dev/null 2>&1 && echo "[OK] Docker 服务可访问" || \
      echo "[注意] 当前用户不能直接访问 Docker，可能需要 sudo 或重新登录"
    docker image inspect "$TARGET_IMAGE" >/dev/null 2>&1 && \
      echo "[OK] ROS 镜像已存在" || echo "[待完成] ROS 镜像尚未下载"
    docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1 && \
      echo "[OK] ROS 容器已存在" || echo "[待完成] ROS 容器尚未创建"
  fi
  [[ -x "$HOME/.local/bin/ros1" ]] && echo "[OK] ros1 命令" || echo "[待完成] ros1 命令"
  [[ -x "$HOME/.local/bin/rostmux" ]] && echo "[OK] rostmux 命令" || echo "[待完成] rostmux 命令"
  local doctor_desktop="${XDG_DESKTOP_DIR:-$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")}/ROS1.desktop"
  [[ -x "$doctor_desktop" ]] && echo "[OK] 桌面入口：$doctor_desktop" || \
    echo "[待完成] 桌面入口：$doctor_desktop"
}

create_desktop_shortcut() {
  local desktop_dir desktop_file app_dir app_file

  if command -v xdg-user-dir >/dev/null 2>&1; then
    desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
  fi
  if [[ -z "${desktop_dir:-}" || "$desktop_dir" == "$HOME" ]]; then
    if [[ -d "$HOME/桌面" ]]; then
      desktop_dir="$HOME/桌面"
    else
      desktop_dir="$HOME/Desktop"
    fi
  fi

  if [[ ! -x "$HOME/.local/bin/launch-rostmux" ]]; then
    [[ -x "$HOME/.local/bin/rostmux" ]] || \
      die "缺少 rostmux 命令，请先完整运行安装脚本。"
    mkdir -p "$HOME/.local/bin"
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'set -Eeuo pipefail' \
      'if command -v ptyxis >/dev/null; then exec ptyxis --new-window --title="ROS 1 分屏" -- bash -lc "exec rostmux"; fi' \
      'if command -v kgx >/dev/null; then exec kgx --title="ROS 1 分屏" -- bash -lc "exec rostmux"; fi' \
      'if command -v gnome-terminal >/dev/null; then exec gnome-terminal --title="ROS 1 分屏" -- bash -lc "exec rostmux"; fi' \
      'if command -v konsole >/dev/null; then exec konsole -e bash -lc "exec rostmux"; fi' \
      'exec x-terminal-emulator -e bash -lc "exec rostmux"' \
      > "$HOME/.local/bin/launch-rostmux"
    chmod 0755 "$HOME/.local/bin/launch-rostmux"
  fi

  app_dir="$HOME/.local/share/applications"
  desktop_file="$desktop_dir/ROS1.desktop"
  app_file="$app_dir/ROS1.desktop"
  mkdir -p "$desktop_dir" "$app_dir"

  for shortcut_file in "$desktop_file" "$app_file"; do
    printf '%s\n' \
      '[Desktop Entry]' \
      'Version=1.0' \
      'Type=Application' \
      'Name=ROS1' \
      'Comment=打开 ROS 1 Noetic 四分屏开发环境' \
      "Exec=$HOME/.local/bin/launch-rostmux" \
      'Icon=utilities-terminal' \
      'Terminal=false' \
      'Categories=Development;' \
      'StartupNotify=true' > "$shortcut_file"
    chmod 0755 "$shortcut_file"
    if command -v desktop-file-validate >/dev/null 2>&1; then
      desktop-file-validate "$shortcut_file"
    fi
  done

  if command -v gio >/dev/null 2>&1; then
    gio set "$desktop_file" metadata::trusted true || \
      echo "警告：无法自动标记桌面图标为可信，请右键图标选择“允许运行”。" >&2
  fi
  command -v update-desktop-database >/dev/null 2>&1 && \
    update-desktop-database "$app_dir" || true

  # GNOME 的桌面由 DING 扩展显示；安装但未启用时主动启用。
  if command -v gnome-extensions >/dev/null 2>&1 && \
    gnome-extensions list | grep -qx 'ding@rastersoft.com'; then
    gnome-extensions enable ding@rastersoft.com || \
      echo "提示：桌面图标扩展将在下次登录后生效。" >&2
  fi

  note "桌面图标已创建：$desktop_file"
  note "应用菜单入口已创建：$app_file"
}

repair_shortcut=false
doctor_mode=false
case "${1:-}" in
  "") ;;
  --repair-shortcut) repair_shortcut=true ;;
  --doctor) doctor_mode=true ;;
  -h|--help)
    sed -n '1,3p' "$0"
    exit 0
    ;;
  *) die "未知参数：$1" ;;
esac

[[ "$EUID" -ne 0 ]] || die "请使用普通用户运行；脚本会在需要时调用 sudo。"
[[ -r /etc/os-release ]] || die "无法识别操作系统。"
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == 26.* ]] || \
  die "此脚本仅面向 Ubuntu 26.x；当前系统：${PRETTY_NAME:-未知}"
command -v sudo >/dev/null || die "未找到 sudo。"

if "$doctor_mode"; then
  show_doctor
  exit 0
fi

log_dir="$HOME/.local/state/ros1-deploy"
mkdir -p "$log_dir"
LOG_FILE="$log_dir/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
note "安装日志：$LOG_FILE"

if "$repair_shortcut"; then
  create_desktop_shortcut
  exit 0
fi

[[ "$(uname -m)" == "x86_64" ]] || \
  die "当前仅支持 amd64/x86_64；osrf/ros:noetic-desktop-full 没有可靠的 ARM 桌面镜像。"
available_kb="$(df -Pk "$HOME" | awk 'NR==2 {print $4}')"
(( available_kb >= 15 * 1024 * 1024 )) || \
  die "磁盘可用空间不足 15 GiB，无法可靠安装完整 ROS 与 Gazebo。"

stage "安装 Docker、tmux 和常用开发工具"
sudo DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 update
sudo DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 install -y \
  docker.io tmux git vim nano htop tree curl wget unzip zip ca-certificates \
  net-tools iputils-ping openssh-client xdg-user-dirs desktop-file-utils \
  gnome-shell-extension-desktop-icons-ng
sudo systemctl enable --now docker

docker_run=(docker)
if ! docker info >/dev/null 2>&1; then
  docker_run=(sudo docker)
  if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
    sudo usermod -aG docker "$USER"
    echo "提示：已把 $USER 加入 docker 组，重新登录后可直接使用 docker。"
  fi
fi

# 重复执行时沿用已有容器的 /workspace 绑定目录，避免覆盖现有工程位置。
if "${docker_run[@]}" container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  existing_workspace="$("${docker_run[@]}" inspect -f \
    '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}' \
    "$CONTAINER_NAME")"
  if [[ -n "$existing_workspace" ]]; then
    PROJECT_DIR="$existing_workspace"
  fi
fi

mkdir -p "$PROJECT_DIR/catkin_ws/src" "$PROJECT_DIR/.ros-home/.ros" "$PROJECT_DIR/.ros1"
touch "$PROJECT_DIR/.ros1/Xauthority"
chmod 0600 "$PROJECT_DIR/.ros1/Xauthority"

stage "准备 ROS 1 Noetic desktop-full 镜像"
if ! "${docker_run[@]}" image inspect "$TARGET_IMAGE" >/dev/null 2>&1; then
  pulled_image=""
  # 前两个是国内 Docker Hub 代理；失效时自动回退官方地址。
  for candidate in \
    "${ROS1_IMAGE_MIRROR:-}" \
    "docker.m.daocloud.io/osrf/ros:noetic-desktop-full" \
    "docker.1ms.run/osrf/ros:noetic-desktop-full" \
    "dockerproxy.net/osrf/ros:noetic-desktop-full" \
    "$TARGET_IMAGE"; do
    [[ -n "$candidate" ]] || continue
    note "尝试拉取 $candidate"
    for pull_attempt in 1 2; do
      if "${docker_run[@]}" pull "$candidate"; then
        pulled_image="$candidate"
        break 2
      fi
      echo "第 $pull_attempt 次拉取失败，切换或重试镜像源。" >&2
    done
  done
  [[ -n "$pulled_image" ]] || \
    die "镜像拉取失败。可设置 ROS1_IMAGE_MIRROR=可用镜像地址 后重新运行。"
  if [[ "$pulled_image" != "$TARGET_IMAGE" ]]; then
    "${docker_run[@]}" tag "$pulled_image" "$TARGET_IMAGE"
  fi
fi

if ! "${docker_run[@]}" container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  stage "创建 ROS 1 容器"
  "${docker_run[@]}" run -d \
    --name "$CONTAINER_NAME" \
    --hostname ros1-course \
    --network host \
    --restart unless-stopped \
    --workdir /workspace/catkin_ws \
    --env HOME=/tmp/ros-home \
    --env "DISPLAY=${DISPLAY:-:0}" \
    --env XAUTHORITY=/tmp/.docker.xauth \
    --env QT_X11_NO_MITSHM=1 \
    --volume "$PROJECT_DIR:/workspace" \
    --volume "$PROJECT_DIR/.ros-home:/tmp/ros-home" \
    --volume /tmp/.X11-unix:/tmp/.X11-unix:rw \
    --volume "$PROJECT_DIR/.ros1/Xauthority:/tmp/.docker.xauth:ro" \
    "$TARGET_IMAGE" sleep infinity >/dev/null

  "${docker_run[@]}" exec --user root "$CONTAINER_NAME" bash -c \
    "getent group $(id -g) >/dev/null || groupadd --gid $(id -g) hostuser; \
     getent passwd $(id -u) >/dev/null || useradd --uid $(id -u) --gid $(id -g) \
       --home-dir /tmp/ros-home --no-create-home hostuser"
elif [[ "$("${docker_run[@]}" inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" != true ]]; then
  "${docker_run[@]}" start "$CONTAINER_NAME" >/dev/null
fi

stage "配置容器用户与用户权限"
"${docker_run[@]}" exec --user root "$CONTAINER_NAME" bash -c \
  "getent group $(id -g) >/dev/null || groupadd --gid $(id -g) hostuser; \
   getent passwd $(id -u) >/dev/null || useradd --uid $(id -u) --gid $(id -g) \
     --home-dir /tmp/ros-home --no-create-home hostuser"

stage "配置国内 ROS 源并安装必需工具"
"${docker_run[@]}" exec --user root "$CONTAINER_NAME" bash -c "
  set -Eeuo pipefail
  printf 'deb ${ROS_MIRROR} focal main\\n' > /etc/apt/sources.list.d/ros1-cn.list
  apt-get -o Acquire::Retries=3 update
  DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 install -y \
    python3-rosdep python3-catkin-tools python3-vcstool
"

stage "安装仿真、导航与视觉扩展包"
if ! "${docker_run[@]}" exec --user root "$CONTAINER_NAME" bash -c "
  DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 install -y \
    ros-noetic-turtlesim ros-noetic-rqt ros-noetic-rqt-graph \
    ros-noetic-rqt-tf-tree ros-noetic-tf2-tools ros-noetic-xacro \
    ros-noetic-urdf-tutorial ros-noetic-joint-state-publisher-gui \
    ros-noetic-teleop-twist-keyboard ros-noetic-joy \
    ros-noetic-gazebo-ros-control ros-noetic-ros-control ros-noetic-ros-controllers \
    ros-noetic-turtlebot3 ros-noetic-turtlebot3-simulations \
    ros-noetic-turtlebot3-navigation ros-noetic-navigation \
    ros-noetic-map-server ros-noetic-slam-gmapping ros-noetic-amcl \
    ros-noetic-robot-localization ros-noetic-image-transport \
    ros-noetic-cv-bridge ros-noetic-vision-opencv ros-noetic-pcl-ros \
    ros-noetic-usb-cam
"; then
  echo "警告：部分扩展包安装失败；ROS desktop-full 主体仍可使用。" >&2
  echo "稍后重新运行脚本即可继续补装。" >&2
fi

stage "配置容器内 ROS 环境"
printf '%s\n' \
  'source /opt/ros/noetic/setup.bash' \
  '[ -f /workspace/catkin_ws/devel/setup.bash ] && source /workspace/catkin_ws/devel/setup.bash' \
  'export ROS_MASTER_URI=http://localhost:11311' \
  'export ROS_HOSTNAME=localhost' \
  'export TURTLEBOT3_MODEL=burger' \
  'export LIBGL_ALWAYS_SOFTWARE=1' \
  'export XDG_RUNTIME_DIR=/tmp/runtime-ros' \
  'mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"' \
  'cd /workspace/catkin_ws' > "$PROJECT_DIR/.ros1/bashrc"

"${docker_run[@]}" exec --user "$(id -u):$(id -g)" \
  --env HOME=/tmp/ros-home --workdir /workspace/catkin_ws \
  "$CONTAINER_NAME" bash -lc \
  'source /opt/ros/noetic/setup.bash; if [ ! -f src/CMakeLists.txt ]; then catkin_make; fi'

stage "部署 ros1、rostmux 命令"
mkdir -p "$HOME/.local/bin"
launcher="$HOME/.local/bin/ros1"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  "container='$CONTAINER_NAME'" \
  "project='$PROJECT_DIR'" \
  'docker_cmd=(docker)' \
  'docker info >/dev/null 2>&1 || docker_cmd=(sudo docker)' \
  'if [ -n "${XAUTHORITY:-}" ] && [ -r "$XAUTHORITY" ]; then cp "$XAUTHORITY" "$project/.ros1/Xauthority"; chmod 0600 "$project/.ros1/Xauthority"; fi' \
  '"${docker_cmd[@]}" start "$container" >/dev/null 2>&1 || true' \
  'tty_args=(); [ -t 0 ] && [ -t 1 ] && tty_args=(-it)' \
  'exec "${docker_cmd[@]}" exec "${tty_args[@]}" --user "$(id -u):$(id -g)" --env HOME=/tmp/ros-home --env "DISPLAY=${DISPLAY:-:0}" --env XAUTHORITY=/tmp/.docker.xauth --workdir /workspace/catkin_ws "$container" bash --rcfile /workspace/.ros1/bashrc -i' \
  > "$launcher"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  "start_dir='$PROJECT_DIR/catkin_ws'" \
  'session="ros1-$(date +%s)-$RANDOM"' \
  'tmux new-session -d -s "$session" -c "$start_dir" ros1' \
  'tmux split-window -h -t "$session":0 -c "$start_dir" ros1' \
  'tmux split-window -v -t "$session":0.0 -c "$start_dir" ros1' \
  'tmux split-window -v -t "$session":0.2 -c "$start_dir" ros1' \
  'tmux select-layout -t "$session":0 tiled' \
  'exec tmux attach-session -t "$session"' > "$HOME/.local/bin/rostmux"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  'if command -v ptyxis >/dev/null; then exec ptyxis --new-window --title="ROS 1 分屏" -- bash -lc "exec rostmux"; fi' \
  'if command -v kgx >/dev/null; then exec kgx --title="ROS 1 分屏" -- bash -lc "exec rostmux"; fi' \
  'if command -v gnome-terminal >/dev/null; then exec gnome-terminal --title="ROS 1 分屏" -- bash -lc "exec rostmux"; fi' \
  'if command -v konsole >/dev/null; then exec konsole -e bash -lc "exec rostmux"; fi' \
  'exec x-terminal-emulator -e bash -lc "exec rostmux"' > "$HOME/.local/bin/launch-rostmux"
chmod 0755 "$HOME/.local/bin/ros1" "$HOME/.local/bin/rostmux" "$HOME/.local/bin/launch-rostmux"
if ! grep -qsF '$HOME/.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

if [[ ! -f "$HOME/.tmux.conf" ]] || ! grep -qs '^set -g mouse on$' "$HOME/.tmux.conf"; then
  {
    echo
    echo '# ROS1 分屏：允许鼠标点击切换窗格和滚动'
    echo 'set -g mouse on'
  } >> "$HOME/.tmux.conf"
fi

stage "创建桌面快捷方式"
create_desktop_shortcut

if command -v code >/dev/null 2>&1; then
  note "安装 VS Code ROS 开发扩展"
  for extension in ms-iot.vscode-ros ms-vscode.cpptools ms-python.python \
    ms-vscode.cmake-tools redhat.vscode-xml redhat.vscode-yaml; do
    code --install-extension "$extension" --force || true
  done
fi

note "部署完成"
echo "项目目录：$PROJECT_DIR"
echo "单终端命令：ros1"
echo "四分屏命令：rostmux"
echo "桌面快捷方式：$(xdg-user-dir DESKTOP)/ROS1.desktop"
echo "若刚加入 docker 组，请重新登录一次系统。"
echo "诊断命令：./install_ros1_ubuntu26.sh --doctor"
echo "完整日志：$LOG_FILE"
