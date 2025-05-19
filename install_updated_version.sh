#!/bin/bash

# 创建并执行安装脚本
cat > /root/install_updated_version.sh << 'EOF'
#!/bin/bash

# 创建更新版本的混合模式签到脚本
cat > /root/updated_tg_hybrid_bot.py << 'EOFPY'
#!/usr/bin/env python3
import os, json, logging, asyncio
from datetime import datetime
from telethon import TelegramClient, events
from telethon.tl.types import PeerUser
from apscheduler.schedulers.asyncio import AsyncIOScheduler

# 配置日志
logging.basicConfig(format='%(asctime)s - %(levelname)s - %(message)s', level=logging.INFO)
logger = logging.getLogger(__name__)

# 配置文件
CONFIG_FILE = '/root/tg_hybrid_config.json'
DEFAULT_CONFIG = {
    'api_id': None,
    'api_hash': None,
    'bot_token': None,
    'user_phone': None,
    'tasks': []
}

# 保存/加载配置
def save_config(config):
    try:
        with open(CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=2)
        logger.info(f"配置已保存到 {CONFIG_FILE}")
        return True
    except Exception as e:
        logger.error(f"保存配置失败: {e}")
        return False

def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                config = json.load(f)
            logger.info(f"已从 {CONFIG_FILE} 加载配置")
            return config
        except Exception as e:
            logger.error(f"加载配置失败: {e}")
            return DEFAULT_CONFIG
    logger.info("使用默认配置")
    return DEFAULT_CONFIG

# 发送命令函数(由用户账户执行)
async def send_command(user_client, username, cmd, retry_interval=300, max_retries=3, retries=0):
    try:
        await user_client.send_message(username, cmd)
        logger.info(f"已发送命令 {cmd} 到 @{username}")
        return True
    except Exception as e:
        logger.error(f"发送命令失败: {e}")
        
        if retries >= max_retries:
            logger.error(f"达到最大重试次数({max_retries})，放弃执行")
            return False
        
        logger.info(f"将在 {retry_interval} 秒后重试 ({retries+1}/{max_retries})")
        await asyncio.sleep(retry_interval)
        return await send_command(user_client, username, cmd, retry_interval, max_retries, retries+1)

# 主程序
async def main():
    # 加载配置
    config = load_config()
    
    # 首次运行初始化配置
    if not config['api_id'] or not config['api_hash'] or not config['bot_token'] or not config['user_phone']:
        print("\n===== Telegram混合模式配置 =====")
        config['api_id'] = int(input("请输入API ID: ").strip())
        config['api_hash'] = input("请输入API Hash: ").strip()
        config['bot_token'] = input("请输入Bot Token: ").strip()
        config['user_phone'] = input("请输入您的手机号码(带国家代码，如+86xxx): ").strip()
        save_config(config)
    
    # 创建机器人客户端
    bot = TelegramClient('hybrid_bot', config['api_id'], config['api_hash'])
    await bot.start(bot_token=config['bot_token'])
    bot_me = await bot.get_me()
    logger.info(f"机器人已启动: @{bot_me.username}")
    
    # 创建用户客户端
    user = TelegramClient('hybrid_user', config['api_id'], config['api_hash'])
    await user.start(phone=config['user_phone'])
    
    if not await user.is_user_authorized():
        logger.info("需要登录您的Telegram账户")
        await user.send_code_request(config['user_phone'])
        code = input("请输入收到的验证码: ")
        await user.sign_in(config['user_phone'], code)
    
    user_me = await user.get_me()
    logger.info(f"用户账户已登录: {user_me.first_name} (@{user_me.username})")
    
    # 创建调度器(用于用户客户端执行任务)
    scheduler = AsyncIOScheduler()
    
    # 加载现有任务
    def load_tasks():
        scheduler.remove_all_jobs()
        for task in config['tasks']:
            h, m = task['time'].split(':')
            if task['type'] == 'daily':
                scheduler.add_job(
                    send_command,
                    args=[user, task['username'], task['cmd'], 300, 3],
                    trigger='cron',
                    hour=int(h),
                    minute=int(m)
                )
            else:  # monthly
                scheduler.add_job(
                    send_command,
                    args=[user, task['username'], task['cmd'], 300, 3],
                    trigger='cron',
                    day=task['day'],
                    hour=int(h),
                    minute=int(m)
                )
        logger.info(f"已加载 {len(config['tasks'])} 个任务")
    
    # 处理/start命令
    @bot.on(events.NewMessage(pattern='/start'))
    async def start_handler(event):
        await event.respond(
            "👋 欢迎使用Telegram签到机器人!\n\n"
            "🔹 /add_daily - 添加每日签到任务\n"
            "🔹 /add_monthly - 添加每月签到任务\n"
            "🔹 /list - 查看所有任务\n"
            "🔹 /delete - 删除指定任务\n"
            "🔹 /help - 显示帮助信息\n\n"
            "添加的任务将由您的个人账户执行"
        )
    
    # 处理/help命令
    @bot.on(events.NewMessage(pattern='/help'))
    async def help_handler(event):
        await event.respond(
            "📌 使用指南:\n\n"
            "1️⃣ 添加每日签到任务:\n"
            "   直接发送: /add_daily [目标机器人用户名] [签到命令] [时间(HH:MM)]\n"
            "   例如: /add_daily SharonNetworkBot /checkin 08:05\n\n"
            "2️⃣ 添加每月签到任务:\n"
            "   直接发送: /add_monthly [目标机器人用户名] [签到命令] [每月几号] [时间(HH:MM)]\n"
            "   例如: /add_monthly miningbot /apply_balance 1 10:00\n\n"
            "3️⃣ 查看所有任务:\n"
            "   /list\n\n"
            "4️⃣ 删除指定任务:\n"
            "   直接发送: /delete [目标机器人用户名] [签到命令] [时间(HH:MM)]\n"
            "   例如: /delete SharonNetworkBot /checkin 08:05"
        )
    
    # 处理/add_daily命令
    @bot.on(events.NewMessage(pattern='/add_daily'))
    async def add_daily_handler(event):
        message = event.message.text.strip()
        parts = message.split()
        
        # 检查格式
        if len(parts) == 4:  # 完整命令: /add_daily username command time
            try:
                _, username, cmd, time_str = parts
                # 验证时间格式
                h, m = time_str.split(':')
                int(h)
                int(m)
                
                task = {
                    'username': username,
                    'cmd': cmd,
                    'time': time_str,
                    'type': 'daily',
                }
                
                config['tasks'].append(task)
                save_config(config)
                
                # 添加到调度器
                h, m = time_str.split(':')
                scheduler.add_job(
                    send_command,
                    args=[user, username, cmd, 300, 3],
                    trigger='cron',
                    hour=int(h),
                    minute=int(m)
                )
                
                await event.respond(f'✅ 已添加每日任务:\n目标: @{username}\n命令: {cmd}\n时间: {time_str}')
                
            except Exception as e:
                await event.respond(f'❌ 添加失败: {str(e)}\n请按格式: /add_daily [用户名] [命令] [时间HH:MM]')
        else:
            await event.respond('请按格式发送: /add_daily [目标机器人用户名] [签到命令] [时间(HH:MM)]\n例如: /add_daily SharonNetworkBot /checkin 08:05')
    
    # 处理/add_monthly命令
    @bot.on(events.NewMessage(pattern='/add_monthly'))
    async def add_monthly_handler(event):
        message = event.message.text.strip()
        parts = message.split()
        
        # 检查格式
        if len(parts) == 5:  # 完整命令: /add_monthly username command day time
            try:
                _, username, cmd, day, time_str = parts
                day = int(day)
                if day < 1 or day > 28:
                    raise ValueError("日期必须在1-28之间")
                
                # 验证时间格式
                h, m = time_str.split(':')
                int(h)
                int(m)
                
                task = {
                    'username': username,
                    'cmd': cmd,
                    'day': day,
                    'time': time_str,
                    'type': 'monthly',
                }
                
                config['tasks'].append(task)
                save_config(config)
                
                # 添加到调度器
                h, m = time_str.split(':')
                scheduler.add_job(
                    send_command,
                    args=[user, username, cmd, 300, 3],
                    trigger='cron',
                    day=day,
                    hour=int(h),
                    minute=int(m)
                )
                
                await event.respond(f'✅ 已添加每月任务:\n目标: @{username}\n命令: {cmd}\n执行时间: 每月{day}号 {time_str}')
                
            except Exception as e:
                await event.respond(f'❌ 添加失败: {str(e)}\n请按格式: /add_monthly [用户名] [命令] [日期] [时间HH:MM]')
        else:
            await event.respond('请按格式发送: /add_monthly [目标机器人用户名] [签到命令] [每月几号] [时间(HH:MM)]\n例如: /add_monthly miningbot /apply_balance 1 10:00')
    
    # 处理/list命令
    @bot.on(events.NewMessage(pattern='/list'))
    async def list_tasks_handler(event):
        tasks = config['tasks']
        
        if not tasks:
            await event.respond('⚠️ 当前没有任务。使用 /add_daily 或 /add_monthly 添加任务。')
            return
        
        message = "📋 任务列表:\n\n"
        for i, task in enumerate(tasks):
            if task['type'] == 'daily':
                message += f"{i+1}. 每日任务: @{task['username']} {task['cmd']} - {task['time']}\n"
            else:
                message += f"{i+1}. 每月任务: @{task['username']} {task['cmd']} - 每月{task['day']}号 {task['time']}\n"
        
        await event.respond(message)
    
    # 处理/delete命令 - 新格式: /delete username command time
    @bot.on(events.NewMessage(pattern='/delete'))
    async def delete_task_handler(event):
        message = event.message.text.strip()
        parts = message.split()
        
        if len(parts) == 1:  # 只有/delete命令
            tasks = config['tasks']
            
            if not tasks:
                await event.respond('⚠️ 当前没有任务可删除。')
                return
            
            message = "请按以下格式删除任务:\n/delete [目标机器人用户名] [签到命令] [时间]\n\n当前任务列表:\n\n"
            for i, task in enumerate(tasks):
                if task['type'] == 'daily':
                    message += f"{i+1}. 每日任务: @{task['username']} {task['cmd']} - {task['time']}\n"
                else:
                    message += f"{i+1}. 每月任务: @{task['username']} {task['cmd']} - 每月{task['day']}号 {task['time']}\n"
            
            await event.respond(message)
            return
        
        # 至少有4个部分: /delete username command time
        if len(parts) >= 4:
            _, username, cmd = parts[0:3]
            
            # 时间可能包含空格, 合并剩余部分
            time_str = parts[3]
            
            tasks = config['tasks']
            tasks_count = len(tasks)
            
            # 查找并删除匹配的任务
            for i in range(len(tasks) - 1, -1, -1):  # 从后向前遍历，以便安全删除
                task = tasks[i]
                if (task['username'] == username and 
                    task['cmd'] == cmd and 
                    task['time'] == time_str):
                    # 找到匹配的任务
                    removed_task = tasks.pop(i)
                    save_config(config)
                    
                    # 重新加载任务
                    load_tasks()
                    
                    if removed_task['type'] == 'daily':
                        await event.respond(f"✅ 已删除每日任务: @{removed_task['username']} {removed_task['cmd']} - {removed_task['time']}")
                    else:
                        await event.respond(f"✅ 已删除每月任务: @{removed_task['username']} {removed_task['cmd']} - 每月{removed_task['day']}号 {removed_task['time']}")
                    return
            
            # 未找到匹配的任务
            await event.respond(f"❌ 未找到匹配的任务: @{username} {cmd} - {time_str}")
        else:
            await event.respond('请按格式发送: /delete [目标机器人用户名] [签到命令] [时间]\n例如: /delete SharonNetworkBot /checkin 08:05')
    
    # 初始加载任务
    load_tasks()
    
    # 启动调度器
    scheduler.start()
    
    logger.info("系统已启动，等待指令...")
    
    # 保持两个客户端运行
    await asyncio.gather(
        bot.run_until_disconnected(),
        user.run_until_disconnected()
    )

# 运行主程序
if __name__ == "__main__":
    asyncio.run(main())
EOFPY

# 设置执行权限
chmod +x /root/updated_tg_hybrid_bot.py

# 安装依赖
apt-get update
apt-get install -y python3-full
python3 -m venv /root/tg_hybrid_env
source /root/tg_hybrid_env/bin/activate
pip install telethon apscheduler

# 创建启动脚本
cat > /root/start_updated_hybrid.sh << 'EOFSH'
#!/bin/bash
source /root/tg_hybrid_env/bin/activate
cd /root
python3 updated_tg_hybrid_bot.py
EOFSH

chmod +x /root/start_updated_hybrid.sh

# 创建系统服务
cat > /etc/systemd/system/tg-updated-hybrid.service << 'EOFSV'
[Unit]
Description=Telegram混合模式签到机器人(更新版)
After=network.target

[Service]
ExecStart=/root/tg_hybrid_env/bin/python /root/updated_tg_hybrid_bot.py
WorkingDirectory=/root
Restart=always
User=root
Group=root
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOFSV

# 重载systemd配置
systemctl daemon-reload

echo "=============================="
echo "✅ 更新版本安装完成!"
echo "您可以通过以下方式运行:"
echo ""
echo "1. 直接运行(前台):"
echo "   /root/start_updated_hybrid.sh"
echo ""
echo "2. 作为系统服务运行(推荐):"
echo "   systemctl enable tg-updated-hybrid.service"
echo "   systemctl start tg-updated-hybrid.service"
echo ""
echo "🔥 使用方法:"
echo "向您的机器人发送以下格式的命令:"
echo "  添加任务: /add_daily SharonNetworkBot /checkin 08:05"
echo "  删除任务: /delete SharonNetworkBot /checkin 08:05"
echo "=============================="

# 启动服务
systemctl enable tg-updated-hybrid.service
systemctl start tg-updated-hybrid.service
EOF

# 设置执行权限并运行
chmod +x /root/install_updated_version.sh
/root/install_updated_version.sh
