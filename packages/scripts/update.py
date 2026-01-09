#!/usr/bin/env python3
"""
Docker 离线安装包自动更新脚本 (GitHub Actions 优化版)
支持 x86_64 和 aarch64 (ARM64) 架构
自动下载最新版本的 Docker、Docker Compose 和相关组件
"""

import os
import sys
import json
import urllib.request
import urllib.error
import hashlib
import shutil
import argparse
from datetime import datetime
from pathlib import Path

# ANSI 颜色代码 - VS Code 风格
class Colors:
    RESET = "\033[0m"
    TIMESTAMP = "\033[0;90m"      # 灰色 - 时间戳
    INFO = "\033[0;36m"           # 青色 - INFO
    SUCCESS = "\033[0;32m"        # 绿色 - SUCCESS
    WARNING = "\033[0;33m"        # 黄色 - WARNING
    ERROR = "\033[0;31m"          # 红色 - ERROR
    DEBUG = "\033[0;35m"          # 品红 - DEBUG
    NOTICE = "\033[1;36m"         # 亮青色 - NOTICE
    KEY = "\033[1;37m"            # 白色 - 关键信息
    VALUE = "\033[0;32m"          # 绿色 - 值
    DIMMED = "\033[0;37m"         # 淡白色 - 详细信息
    BOLD = "\033[1m"              # 加粗

class DockerUpdater:
    def __init__(self, output_dir="./packages", architectures=None, ci_mode=False):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)
        self.ci_mode = ci_mode
        
        self.architectures = architectures or ["x86_64", "aarch64"]
        
        self.arch_mapping = {
            "x86_64": {
                "docker_arch": "x86_64",
                "compose_arch": "x86_64",
                "display_name": "x86_64 (AMD64)"
            },
            "aarch64": {
                "docker_arch": "aarch64",
                "compose_arch": "aarch64",
                "display_name": "ARM64 (aarch64)"
            }
        }
        
        self.docker_url_template = "https://download.docker.com/linux/static/stable/{arch}/docker-{version}.tgz"
        self.compose_url_template = "https://github.com/docker/compose/releases/download/v{version}/docker-compose-linux-{arch}"
        self.rootless_url_template = "https://download.docker.com/linux/static/stable/{arch}/docker-rootless-extras-{version}.tgz"
        
        self.log_file = self.output_dir / f"update_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
        
        self.download_stats = {
            'success': 0,
            'failed': 0,
            'skipped': 0,
            'total_size': 0
        }
    
    def log(self, message, level="INFO", icon=""):
        """输出日志消息"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        level_padded = f"[{level:<7}]"
        
        # 确定颜色
        color_map = {
            "INFO": Colors.INFO,
            "SUCCESS": Colors.SUCCESS,
            "WARNING": Colors.WARNING,
            "ERROR": Colors.ERROR,
            "DEBUG": Colors.DEBUG,
            "NOTICE": Colors.NOTICE,
        }
        color = color_map.get(level, Colors.INFO)
        
        # 添加图标空格（仅当有图标时）
        icon_str = f"{icon} " if icon else ""
        
        # 构建输出
        if self.ci_mode:
            # GitHub Actions 日志格式
            if level == "ERROR":
                output = f"::error::{icon_str}{message}"
            elif level == "WARNING":
                output = f"::warning::{icon_str}{message}"
            elif level == "NOTICE":
                output = f"::notice::{icon_str}{message}"
            else:
                output = f"{Colors.TIMESTAMP}{timestamp}{Colors.RESET} {color}{level_padded}{Colors.RESET} {icon_str}{message}"
        else:
            output = f"{Colors.TIMESTAMP}{timestamp}{Colors.RESET} {color}{level_padded}{Colors.RESET} {icon_str}{message}"
        
        print(output)
        
        # 写入日志文件（移除颜色代码）
        clean_message = message
        for color_code in [Colors.KEY, Colors.VALUE, Colors.RESET, Colors.DIMMED]:
            clean_message = clean_message.replace(color_code, "")
        with open(self.log_file, "a", encoding="utf-8") as f:
            f.write(f"[{timestamp}] [{level}] {clean_message}\n")
    
    def set_output(self, name, value):
        """设置 GitHub Actions 输出变量"""
        if self.ci_mode and os.getenv('GITHUB_OUTPUT'):
            with open(os.getenv('GITHUB_OUTPUT'), 'a') as f:
                f.write(f"{name}={value}\n")
    
    def check_url_exists(self, url):
        try:
            req = urllib.request.Request(url, method="HEAD")
            req.add_header('User-Agent', 'Mozilla/5.0')
            with urllib.request.urlopen(req, timeout=20) as _:
                return True
        except Exception:
            return False
    
    def list_static_versions(self, arch):
        try:
            index_url = f"https://download.docker.com/linux/static/stable/{arch}/"
            req = urllib.request.Request(index_url)
            req.add_header('User-Agent', 'Mozilla/5.0')
            with urllib.request.urlopen(req, timeout=30) as resp:
                html = resp.read().decode()
            import re
            versions = re.findall(r'docker-(\d+\.\d+\.\d+)\.tgz', html)
            versions = sorted(set(versions), key=lambda v: tuple(map(int, v.split('.'))), reverse=True)
            return versions
        except Exception as e:
            self.log(f"列举静态版本失败: {e}", "ERROR", "✗")
            return []
    
    def list_rootless_versions(self, arch):
        try:
            index_url = f"https://download.docker.com/linux/static/stable/{arch}/"
            req = urllib.request.Request(index_url)
            req.add_header('User-Agent', 'Mozilla/5.0')
            with urllib.request.urlopen(req, timeout=30) as resp:
                html = resp.read().decode()
            import re
            versions = re.findall(r'docker-rootless-extras-(\d+\.\d+\.\d+)\.tgz', html)
            versions = sorted(set(versions), key=lambda v: tuple(map(int, v.split('.'))), reverse=True)
            return versions
        except Exception as e:
            self.log(f"列举 rootless 版本失败: {e}", "ERROR", "✗")
            return []
    
    def resolve_static_version_for_arch(self, arch, desired_version):
        docker_url = self.docker_url_template.format(arch=arch, version=desired_version)
        if self.check_url_exists(docker_url):
            return desired_version
        avail = self.list_static_versions(arch)
        if avail:
            fallback = avail[0]
            self.log(f"目标版本 {Colors.KEY}{desired_version}{Colors.RESET} 不存在，{arch} 回退到可用版本 {Colors.VALUE}{fallback}{Colors.RESET}", "WARNING", "⊘")
            return fallback
        self.log(f"{arch} 未发现任何可用静态版本，继续尝试目标版本 {Colors.KEY}{desired_version}{Colors.RESET}", "ERROR", "✗")
        return desired_version
    
    def get_latest_docker_version(self):
        """获取最新的 Docker 版本号"""
        try:
            self.log("正在获取最新 Docker 版本...", "INFO", "🔍")
            url = "https://api.github.com/repos/moby/moby/releases/latest"
            req = urllib.request.Request(url)
            req.add_header('User-Agent', 'Mozilla/5.0')
            req.add_header('Accept', 'application/vnd.github.v3+json')
            
            with urllib.request.urlopen(req, timeout=30) as response:
                data = json.loads(response.read().decode())
                tag = data['tag_name']
                import re
                m = re.search(r'(\d+\.\d+\.\d+)', tag)
                version = m.group(1) if m else tag.lstrip('v').replace('docker-', '').replace('engine-', '')
                self.log(f"找到最新 Docker 版本: {Colors.VALUE}{version}{Colors.RESET}", "NOTICE", "✓")
                self.set_output('docker_version', version)
                return version
        except Exception as e:
            self.log(f"获取 Docker 版本失败: {e}", "ERROR", "✗")
            return "27.4.1"
    
    def get_latest_compose_version(self):
        """获取最新的 Docker Compose 版本号"""
        try:
            self.log("正在获取最新 Docker Compose 版本...", "INFO", "🔍")
            url = "https://api.github.com/repos/docker/compose/releases/latest"
            req = urllib.request.Request(url)
            req.add_header('User-Agent', 'Mozilla/5.0')
            req.add_header('Accept', 'application/vnd.github.v3+json')
            
            with urllib.request.urlopen(req, timeout=30) as response:
                data = json.loads(response.read().decode())
            tag = data['tag_name']
            import re
            m = re.search(r'(\d+\.\d+\.\d+)', tag)
            version = m.group(1) if m else tag.lstrip('v')
            self.log(f"找到最新 Docker Compose 版本: {Colors.VALUE}{version}{Colors.RESET}", "NOTICE", "✓")
            self.set_output('compose_version', version)
            return version
        except Exception as e:
            self.log(f"获取 Docker Compose 版本失败: {e}", "ERROR", "✗")
            return "2.32.4"
    
    def get_compose_asset_url(self, version, arch):
        try:
            tag = f"v{version}"
            api = f"https://api.github.com/repos/docker/compose/releases/tags/{tag}"
            req = urllib.request.Request(api)
            req.add_header('User-Agent', 'Mozilla/5.0')
            req.add_header('Accept', 'application/vnd.github.v3+json')
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode())
            assets = data.get('assets', [])
            names = [f"docker-compose-linux-{arch}", f"docker-compose-linux-{arch}.exe"]
            alt = {"x86_64": ["amd64"], "aarch64": ["arm64"]}.get(arch, [])
            for a in alt:
                names.append(f"docker-compose-linux-{a}")
                names.append(f"docker-compose-linux-{a}.exe")
            for asset in assets:
                name = asset.get('name', '')
                url = asset.get('browser_download_url')
                if any(name == n for n in names):
                    return url
                if name.startswith("docker-compose-linux-"):
                    if arch in name or any(a in name for a in alt):
                        return url
            return None
        except Exception as e:
            self.log(f"获取 Compose 资源失败: {e}", "ERROR", "✗")
            return None
    
    def calculate_file_hash(self, filepath, algorithm='sha256'):
        """计算文件哈希值"""
        hash_obj = hashlib.new(algorithm)
        with open(filepath, 'rb') as f:
            for chunk in iter(lambda: f.read(8192), b''):
                hash_obj.update(chunk)
        return hash_obj.hexdigest()
    
    def download_file(self, url, filename, description, max_retries=3):
        """下载文件并显示进度，支持重试"""
        filepath = self.output_dir / filename
        
        # 检查文件是否已存在
        if filepath.exists():
            self.log(f"文件已存在，跳过下载: {Colors.KEY}{filename}{Colors.RESET}", "WARNING", "⊘")
            self.download_stats['skipped'] += 1
            return True
        
        for attempt in range(max_retries):
            try:
                if attempt > 0:
                    self.log(f"重试下载 ({attempt + 1}/{max_retries}): {description}", "INFO", "🔄")
                else:
                    self.log(f"开始下载 {description}...", "INFO", "📥")
                
                self.log(f"  → URL: {Colors.DIMMED}{url}{Colors.RESET}", "DEBUG", "")
                
                req = urllib.request.Request(url)
                req.add_header('User-Agent', 'Mozilla/5.0')
                
                with urllib.request.urlopen(req, timeout=120) as response:
                    total_size = int(response.headers.get('content-length', 0))
                    block_size = 8192
                    downloaded = 0
                    
                    with open(filepath, 'wb') as f:
                        while True:
                            buffer = response.read(block_size)
                            if not buffer:
                                break
                            
                            downloaded += len(buffer)
                            f.write(buffer)
                            
                            # 在 CI 模式下每 10MB 输出一次进度
                            if self.ci_mode and total_size > 0:
                                if downloaded % (10 * 1024 * 1024) < block_size:
                                    percent = (downloaded / total_size) * 100
                                    self.log(f"下载进度: {Colors.VALUE}{percent:.1f}%{Colors.RESET} ({downloaded}/{total_size} bytes)", "DEBUG", "📊")
                            elif total_size > 0 and downloaded % (5 * 1024 * 1024) < block_size:
                                percent = (downloaded / total_size) * 100
                                print(f"\r{Colors.DIMMED}  → 下载进度: {Colors.VALUE}{percent:.1f}%{Colors.RESET} ({Colors.VALUE}{downloaded}/{total_size}{Colors.RESET} bytes){Colors.RESET}", end='', flush=True)
                    
                    if not self.ci_mode and total_size > 0:
                        print()  # 换行
                    
                    # 计算文件哈希
                    file_hash = self.calculate_file_hash(filepath)
                    file_size = filepath.stat().st_size
                    file_size_mb = file_size / (1024 * 1024)
                    
                    self.log(f"{description} 下载完成", "SUCCESS", "✓")
                    self.log(f"  → 文件路径: {Colors.VALUE}{filepath}{Colors.RESET}", "DEBUG", "")
                    self.log(f"  → 文件大小: {Colors.VALUE}{file_size_mb:.2f} MB{Colors.RESET}", "DEBUG", "")
                    self.log(f"  → SHA256: {Colors.DIMMED}{file_hash}{Colors.RESET}", "DEBUG", "")
                    
                    self.download_stats['success'] += 1
                    self.download_stats['total_size'] += file_size
                    
                    return True
                    
            except urllib.error.HTTPError as e:
                self.log(f"HTTP 错误 {e.code}: {description}", "ERROR", "✗")
                if e.code == 404:
                    self.download_stats['failed'] += 1
                    return False
            except Exception as e:
                self.log(f"下载失败: {e}", "ERROR", "✗")
                if filepath.exists():
                    filepath.unlink()
            
            if attempt < max_retries - 1:
                import time
                wait_time = 2 ** attempt
                self.log(f"等待 {Colors.VALUE}{wait_time}${Colors.RESET} 秒后重试...", "INFO", "⏳")
                time.sleep(wait_time)
        
        self.download_stats['failed'] += 1
        return False
    
    def cleanup_old_versions(self, current_docker_version, current_compose_version, arch):
        """清理指定架构的旧版本文件"""
        try:
            import re
            
            # 清理docker旧版本
            docker_pattern = f"docker-*-{arch}.tgz"
            docker_files = list(self.output_dir.glob(docker_pattern))
            for file in docker_files:
                match = re.match(r'docker-(\d+\.\d+\.\d+)-.+\.tgz', file.name)
                if match:
                    file_version = match.group(1)
                    if file_version != current_docker_version:
                        file.unlink()
                        self.log(f"已删除旧版本: {Colors.VALUE}{file.name}${Colors.RESET}", "DEBUG", "🗑️ ")
            
            # 清理docker-rootless-extras旧版本
            rootless_pattern = f"docker-rootless-extras-*-{arch}.tgz"
            rootless_files = list(self.output_dir.glob(rootless_pattern))
            for file in rootless_files:
                match = re.match(r'docker-rootless-extras-(\d+\.\d+\.\d+)-.+\.tgz', file.name)
                if match:
                    file_version = match.group(1)
                    if file_version != current_docker_version:
                        file.unlink()
                        self.log(f"已删除旧版本: {Colors.VALUE}{file.name}${Colors.RESET}", "DEBUG", "🗑️ ")
            
            # 清理docker-compose旧版本
            compose_pattern = f"docker-compose-linux-*-{arch}"
            compose_files = list(self.output_dir.glob(compose_pattern))
            for file in compose_files:
                match = re.match(r'docker-compose-linux-(\d+\.\d+\.\d+)-.+', file.name)
                if match:
                    file_version = match.group(1)
                    if file_version != current_compose_version:
                        file.unlink()
                        self.log(f"已删除旧版本: {Colors.VALUE}{file.name}${Colors.RESET}", "DEBUG", "🗑️ ")
                    
        except Exception as e:
            self.log(f"清理旧文件时出错: {e}", "ERROR", "✗")
    
    def cleanup_logs(self, keep_count=3):
        try:
            logs = sorted(self.output_dir.glob("update_log_*.txt"), key=lambda x: x.stat().st_mtime, reverse=True)
            for old_log in logs[keep_count:]:
                old_log.unlink()
                self.log(f"已删除旧日志: {Colors.VALUE}{old_log.name}${Colors.RESET}", "DEBUG", "🗑️ ")
        except Exception as e:
            self.log(f"清理日志时出错: {e}", "ERROR", "✗")
    
    def create_version_info(self, docker_version, compose_version):
        """创建版本信息文件"""
        version_info = {
            "docker_version": docker_version,
            "compose_version": compose_version,
            "update_date": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "architectures": self.architectures,
            "download_stats": self.download_stats
        }
        
        version_file = self.output_dir / "VERSION.json"
        with open(version_file, "w", encoding="utf-8") as f:
            json.dump(version_info, f, indent=2, ensure_ascii=False)
        
        self.log(f"版本信息已保存: {Colors.VALUE}{version_file}{Colors.RESET}", "SUCCESS", "✓")
    
    def create_checksums_file(self):
        """创建校验和文件"""
        checksums_file = self.output_dir / "SHA256SUMS"
        
        with open(checksums_file, 'w') as f:
            for file in sorted(self.output_dir.glob("*")):
                if file.is_file() and file.suffix in ['.tgz', ''] and file.name != 'SHA256SUMS':
                    sha256 = self.calculate_file_hash(file)
                    f.write(f"{sha256}  {file.name}\n")
        
        self.log(f"校验和文件已创建: {Colors.VALUE}{checksums_file}{Colors.RESET}", "SUCCESS", "✓")
        
    def download_for_architecture(self, arch, docker_version, compose_version):
        """为特定架构下载所有组件"""
        arch_info = self.arch_mapping[arch]
        self.log("", "NOTICE", "")  # 空行
        self.log("=" * 60, "NOTICE", "")
        self.log(f"开始下载 {Colors.VALUE}{arch_info['display_name']}{Colors.RESET} 架构文件", "NOTICE", "📦")
        self.log("=" * 60, "NOTICE", "")
        self.log("", "NOTICE", "")  # 空行
        
        results = []
        
        # 下载 Docker 二进制包
        docker_filename = f"docker-{docker_version}-{arch}.tgz"
        docker_url = self.docker_url_template.format(
            arch=arch_info['docker_arch'],
            version=docker_version
        )
        results.append(self.download_file(docker_url, docker_filename, f"Docker 二进制包 ({arch})"))
        
        # 下载 Docker Compose
        compose_asset_url = self.get_compose_asset_url(compose_version, arch_info['compose_arch'])
        if compose_asset_url:
            compose_filename = f"docker-compose-linux-{compose_version}-{arch}"
            if self.download_file(compose_asset_url, compose_filename, f"Docker Compose ({arch})"):
                os.chmod(self.output_dir / compose_filename, 0o755)
                results.append(True)
            else:
                results.append(False)
        else:
            results.append(False)
        
        # 下载 Docker Rootless Extras
        rootless_filename = f"docker-rootless-extras-{docker_version}-{arch}.tgz"
        rootless_url = self.rootless_url_template.format(
            arch=arch_info['docker_arch'],
            version=docker_version
        )
        if self.download_file(rootless_url, rootless_filename, f"Docker Rootless Extras ({arch})"):
            results.append(True)
        else:
            avail_rootless = self.list_rootless_versions(arch_info['docker_arch'])
            if avail_rootless:
                fallback = avail_rootless[0]
                self.log(f"Rootless Extras 版本 {Colors.KEY}{docker_version}{Colors.RESET} 不存在，{Colors.VALUE}{arch_info['display_name']}{Colors.RESET} 回退到 {Colors.VALUE}{fallback}{Colors.RESET}", "WARNING", "⊘")
                rootless_filename_fb = f"docker-rootless-extras-{fallback}-{arch}.tgz"
                rootless_url_fb = self.rootless_url_template.format(
                    arch=arch_info['docker_arch'],
                    version=fallback
                )
                results.append(self.download_file(rootless_url_fb, rootless_filename_fb, f"Docker Rootless Extras (fallback {arch})"))
            else:
                results.append(False)
        
        success_count = sum(results)
        total_count = len(results)
        
        status_icon = "✓" if success_count == total_count else "⚠️"
        status_level = "NOTICE" if success_count == total_count else "WARNING"
        self.log(f"{Colors.VALUE}{arch_info['display_name']}{Colors.RESET} 架构下载完成: {Colors.VALUE}{success_count}/{total_count}{Colors.RESET}", status_level, status_icon)
        self.log("", "NOTICE", "")  # 空行
        
        return success_count, total_count
    
    def update(self):
        """执行更新流程"""
        self.log("", "NOTICE", "")
        self.log("=" * 60, "NOTICE", "")
        self.log("开始 Docker 离线安装包更新流程", "NOTICE", "🚀")
        self.log(f"支持架构: {Colors.VALUE}{', '.join([self.arch_mapping[a]['display_name'] for a in self.architectures])}{Colors.RESET}", "INFO", "")
        self.log("=" * 60, "NOTICE", "")
        
        # 获取最新版本号
        docker_version = self.get_latest_docker_version()
        compose_version = self.get_latest_compose_version()
        
        self.log("", "NOTICE", "")
        
        total_success = 0
        total_count = 0
        
        # 为每个架构解析可用版本并下载文件
        for arch in self.architectures:
            resolved_version = self.resolve_static_version_for_arch(self.arch_mapping[arch]['docker_arch'], docker_version)
            success, count = self.download_for_architecture(arch, resolved_version, compose_version)
            total_success += success
            total_count += count
        
        # 创建校验和文件
        self.create_checksums_file()
        
        # 创建版本信息
        self.create_version_info(docker_version, compose_version)
        
        # 清理旧版本文件与日志
        for arch in self.architectures:
            resolved_docker_version = self.resolve_static_version_for_arch(self.arch_mapping[arch]['docker_arch'], docker_version)
            self.cleanup_old_versions(resolved_docker_version, compose_version, arch)
            
        self.cleanup_logs(keep_count=3)
        
        # 总结
        self.log("", "NOTICE", "")
        self.log("=" * 60, "NOTICE", "")
        status_icon = "✓" if total_success == total_count else "⚠️"
        status_level = "NOTICE" if total_success == total_count else "WARNING"
        self.log(f"更新完成! 成功: {Colors.VALUE}{total_success}{Colors.RESET}/{Colors.VALUE}{total_count}{Colors.RESET}", status_level, status_icon)
        self.log("下载统计:", "INFO", "📊")
        self.log(f"  → 成功: {Colors.VALUE}{self.download_stats['success']}{Colors.RESET}", "INFO", "")
        self.log(f"  → 失败: {Colors.VALUE}{self.download_stats['failed']}{Colors.RESET}", "INFO", "")
        self.log(f"  → 跳过: {Colors.VALUE}{self.download_stats['skipped']}{Colors.RESET}", "INFO", "")
        self.log(f"  → 总大小: {Colors.VALUE}{self.download_stats['total_size'] / (1024*1024):.2f} MB{Colors.RESET}", "INFO", "")
        self.log(f"输出目录: {Colors.VALUE}{self.output_dir.absolute()}{Colors.RESET}", "INFO", "")
        self.log(f"日志文件: {Colors.VALUE}{self.log_file}{Colors.RESET}", "INFO", "")
        self.log("=" * 60, "NOTICE", "")
        
        # 设置 GitHub Actions 输出
        self.set_output('success_count', str(total_success))
        self.set_output('total_count', str(total_count))
        self.set_output('total_size_mb', f"{self.download_stats['total_size'] / (1024*1024):.2f}")
        
        return total_success == total_count


def main():
    # 检查 Python 版本
    if sys.version_info < (3, 6):
        print("错误: 需要 Python 3.6 或更高版本")
        sys.exit(1)
    
    # 命令行参数解析
    parser = argparse.ArgumentParser(
        description='Docker 离线安装包自动更新工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  %(prog)s                          # 下载所有架构到默认目录
  %(prog)s -a x86_64               # 仅下载 x86_64 架构
  %(prog)s -a aarch64              # 仅下载 ARM64 架构
  %(prog)s -o ./custom-dir         # 指定输出目录
  %(prog)s --ci                    # CI 模式（GitHub Actions）
        """
    )
    parser.add_argument('-o', '--output', 
                        default='./packages',
                        help='输出目录 (默认: ./packages)')
    parser.add_argument('-a', '--arch', 
                        nargs='+', 
                        choices=['x86_64', 'aarch64', 'all'],
                        default=['all'],
                        help='指定架构 (默认: all)')
    parser.add_argument('--ci', 
                        action='store_true',
                        help='CI 模式（优化日志输出）')
    
    args = parser.parse_args()
    
    # 处理架构参数
    if 'all' in args.arch:
        architectures = ['x86_64', 'aarch64']
    else:
        architectures = args.arch
    
    # 检测是否在 GitHub Actions 中运行
    ci_mode = args.ci or os.getenv('GITHUB_ACTIONS') == 'true'
    
    # 创建更新器实例
    updater = DockerUpdater(
        output_dir=args.output, 
        architectures=architectures,
        ci_mode=ci_mode
    )
    
    # 执行更新
    success = updater.update()
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()