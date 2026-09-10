# ROS 1 国内镜像自动部署

## Ubuntu 26.04

Ubuntu 26.04 无法原生安装 ROS 1 Noetic，使用容器部署脚本：

```bash
chmod +x install_ros1_ubuntu26.sh
./install_ros1_ubuntu26.sh
```

它会安装 Docker、tmux 和开发工具，运行 Noetic `desktop-full` 容器，安装常用仿真/导航/视觉包，并创建 `ros1`、`rostmux` 命令及桌面快捷方式。默认工程目录为 `~/ROS1`；可在首次运行时用 `ROS1_HOME=/目标目录 ./install_ros1_ubuntu26.sh` 修改。脚本可重复执行，已有同名容器会继续沿用原来的工程目录。

如果 ROS 已安装完成，但桌面没有出现 `ROS1` 图标，不需要重新安装，执行：

```bash
./install_ros1_ubuntu26.sh --repair-shortcut
```

脚本会把入口同时写入实际桌面目录和 `~/.local/share/applications`，设置为可信可执行，并启用 GNOME 的 Desktop Icons NG 扩展。因此也可以在应用菜单中搜索 `ROS1` 启动。

如果安装中断，修复网络后直接重复运行即可。查看环境和完成状态：

```bash
./install_ros1_ubuntu26.sh --doctor
```

每次安装的完整日志保存在 `~/.local/state/ros1-deploy/`。脚本会预检 Ubuntu 版本、amd64 架构和至少 15 GiB 可用空间，Docker 镜像支持多个国内地址重试。若有自选镜像代理，可使用：

```bash
ROS1_IMAGE_MIRROR=镜像地址/osrf/ros:noetic-desktop-full ./install_ros1_ubuntu26.sh
```

## Ubuntu 20.04

`install_ros1_cn.sh` 会在 **Ubuntu 20.04** 上完整安装 ROS 1 Noetic，并使用中科大 ROS 软件镜像。它会配置签名密钥、初始化 `rosdep`、创建 `~/catkin_ws`，并将 ROS 环境写入 `~/.bashrc`。

默认还会安装之前学习路线所需的常用包：

- 入门与调试：`turtlesim`、rqt/rqt_graph、TF 工具、键盘遥控与手柄支持；
- 建模与仿真：URDF/Xacro、RViz、Gazebo 控制插件、TurtleBot3 仿真与导航；
- 算法与传感器：Navigation/AMCL、GMapping、地图服务、robot_localization、图像传输、OpenCV、PCL 和 USB 摄像头。
- 开发工具：tmux、Git、Vim、Nano、htop、tree、网络诊断工具、catkin-tools 和 vcstool。

安装完成后会部署 `rostmux` 命令。运行它会打开一个独立的 ROS 工作会话，并自动创建四个 tmux 分屏。脚本还会在当前用户桌面创建 `ROS1` 快捷方式，双击即可进入四分屏；如果系统已经安装 VS Code，也会安装 ROS、C/C++、Python、CMake、XML 和 YAML 扩展。

执行：

```bash
chmod +x install_ros1_cn.sh
./install_ros1_cn.sh
```

默认安装 `desktop-full`。如只需较轻量的环境：

```bash
./install_ros1_cn.sh desktop
./install_ros1_cn.sh ros-base
```

默认会连同上述实用包一起安装。若只希望安装 ROS 主体和编译工具，追加 `--skip-extras`：

```bash
./install_ros1_cn.sh ros-base --skip-extras
```

安装结束后运行 `source ~/.bashrc`，再用 `roscore` 验证。TurtleBot3 仿真可直接运行 `roslaunch turtlebot3_gazebo turtlebot3_world.launch`。脚本需要普通用户具有 `sudo` 权限。ROS 1 Noetic 已停止维护；在非 Ubuntu 20.04 系统上，建议使用容器方案而非混用软件源。
