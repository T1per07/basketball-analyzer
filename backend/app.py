"""FastAPI 主应用 - 篮球投篮分析 API"""
import uuid
import asyncio
import json
import base64
import logging
import time
from pathlib import Path
from dataclasses import dataclass

import cv2
import numpy as np
from fastapi import FastAPI, UploadFile, File, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from services.video_processor import VideoProcessor
from services.stats_calculator import StatsCalculator
from services.realtime_service import RealtimeAnalyzer
from config.settings import config

logger = logging.getLogger(__name__)

# ── 安全配置（从 config 统一读取）──
MAX_UPLOAD_SIZE_BYTES = config.security.max_upload_size_mb * 1024 * 1024
ALLOWED_VIDEO_EXTENSIONS = set(config.security.allowed_video_extensions)
ALLOWED_ORIGINS = list(config.security.allowed_origins)

app = FastAPI(
    title="Basketball Shot Analyzer",
    description="篮球投篮分析系统 - 检测、跟踪、轨迹分析、统计",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 存储分析任务状态
@dataclass
class TaskState:
    task_id: str
    status: str  # "processing", "completed", "failed"
    progress: float
    video_path: str
    result: dict | None = None
    error: str | None = None


tasks: dict[str, TaskState] = {}
_video_tasks: set[asyncio.Task] = set()  # 持有异步任务引用，防止 GC 回收
video_processor = VideoProcessor()
stats_calculator = StatsCalculator()


@app.get("/api")
async def api_info():
    return {
        "name": "Basketball Shot Analyzer",
        "version": "0.1.0",
        "endpoints": {
            "upload": "POST /api/v1/analyze",
            "status": "GET /api/v1/status/{task_id}",
            "results": "GET /api/v1/results/{task_id}",
            "video": "GET /api/v1/videos/{task_id}",
        },
    }


@app.post("/api/v1/analyze")
async def analyze_video(file: UploadFile = File(...)):
    """上传视频并开始分析"""
    # 格式白名单校验
    if not file.filename:
        raise HTTPException(400, "Filename is required")
    ext = Path(file.filename).suffix.lower()
    if ext not in ALLOWED_VIDEO_EXTENSIONS:
        raise HTTPException(400, f"Unsupported video format: {ext}. Allowed: {', '.join(ALLOWED_VIDEO_EXTENSIONS)}")

    if not file.content_type or not file.content_type.startswith("video/"):
        raise HTTPException(400, "File must be a video")

    task_id = str(uuid.uuid4())[:8]
    upload_dir = config.video_upload_dir
    upload_dir.mkdir(parents=True, exist_ok=True)

    # 流式读取并限制大小，防止超大文件耗尽内存
    video_path = str(upload_dir / f"{task_id}_{file.filename}")
    total_size = 0
    chunk_size = 1024 * 1024  # 1MB per chunk
    with open(video_path, "wb") as f:
        while True:
            chunk = await file.read(chunk_size)
            if not chunk:
                break
            total_size += len(chunk)
            if total_size > MAX_UPLOAD_SIZE_BYTES:
                f.close()
                Path(video_path).unlink(missing_ok=True)
                raise HTTPException(413, f"File too large. Max size: {MAX_UPLOAD_SIZE_BYTES // (1024*1024)}MB")
            f.write(chunk)

    tasks[task_id] = TaskState(
        task_id=task_id,
        status="processing",
        progress=0.0,
        video_path=video_path,
    )

    # 异步处理视频（持有任务引用防止 GC 回收）
    task = asyncio.create_task(_process_video(task_id, video_path))
    _video_tasks.add(task)
    task.add_done_callback(_video_tasks.discard)

    return {
        "task_id": task_id,
        "status": "processing",
        "message": "Video uploaded, analysis started",
    }


async def _process_video(task_id: str, video_path: str):
    """异步处理视频（在后台线程中运行，不阻塞事件循环）"""
    try:
        def progress_cb(current, total):
            tasks[task_id].progress = current / total if total > 0 else 0

        def run_analysis():
            result = video_processor.analyze_video(video_path, progress_cb)
            # 获取视频真实分辨率，用于热力图坐标归一化
            video_info = video_processor.get_video_info(video_path)
            full_stats = stats_calculator.generate_full_stats(
                result,
                image_width=video_info.width,
                image_height=video_info.height,
            )

            # 添加投篮详情（转为原生 Python 类型避免 numpy 序列化问题）
            full_stats["shots"] = [
                {
                    "shot_id": int(s.shot_id),
                    "shot_type": str(s.shot_type),
                    "made": bool(s.made),
                    "distance": float(s.distance),
                    "release_angle": float(s.release_angle),
                    "entry_angle": float(s.entry_angle),
                    "confidence": float(s.confidence),
                    "frame": int(s.frame_end),
                }
                for s in result.shots
            ]

            # 生成标注视频（60fps）
            output_dir = config.output_dir
            output_dir.mkdir(parents=True, exist_ok=True)
            annotated_path = str(output_dir / f"{task_id}_annotated.mp4")

            video_processor.create_annotated_video(
                video_path, annotated_path, result, progress_cb
            )

            return full_stats

        full_stats = await asyncio.to_thread(run_analysis)

        tasks[task_id].status = "completed"
        tasks[task_id].progress = 1.0
        tasks[task_id].result = {
            **full_stats,
            "annotated_video": f"/api/v1/videos/{task_id}",
        }

    except Exception as e:
        import traceback
        traceback.print_exc()
        tasks[task_id].status = "failed"
        tasks[task_id].error = str(e)


@app.get("/api/v1/status/{task_id}")
async def get_status(task_id: str):
    """获取分析进度"""
    if task_id not in tasks:
        raise HTTPException(404, "Task not found")

    task = tasks[task_id]
    return {
        "task_id": task.task_id,
        "status": task.status,
        "progress": task.progress,
    }


@app.get("/api/v1/results/{task_id}")
async def get_results(task_id: str):
    """获取分析结果"""
    if task_id not in tasks:
        raise HTTPException(404, "Task not found")

    task = tasks[task_id]
    if task.status == "processing":
        raise HTTPException(202, "Analysis still in progress")
    if task.status == "failed":
        raise HTTPException(500, f"Analysis failed: {task.error}")

    return {
        "task_id": task.task_id,
        "status": task.status,
        **task.result,
    }


@app.get("/api/v1/videos/{task_id}")
async def get_video(task_id: str):
    """获取标注后的视频"""
    if task_id not in tasks:
        raise HTTPException(404, "Task not found")

    video_path = config.output_dir / f"{task_id}_annotated.mp4"
    if not video_path.exists():
        raise HTTPException(404, "Video not found")

    return FileResponse(str(video_path), media_type="video/mp4")


@app.get("/api/v1/health")
async def health():
    return {"status": "ok"}


@app.websocket("/ws/realtime")
async def websocket_realtime(websocket: WebSocket):
    """
    WebSocket 实时视频流分析
    客户端发送: base64 编码的 JPEG 帧
    服务端返回: 分析结果 + 标注后的帧
    """
    await websocket.accept()
    analyzer = RealtimeAnalyzer()

    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)

            if msg.get("type") == "reset":
                analyzer.reset()
                await websocket.send_json({"type": "reset_ack"})
                continue

            if msg.get("type") != "frame":
                continue

            # 解码帧
            frame_data = base64.b64decode(msg["data"])
            np_arr = np.frombuffer(frame_data, np.uint8)
            frame = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

            if frame is None:
                continue

            # 处理帧
            result = analyzer.process_frame(frame)

            # 编码标注帧
            annotated_b64 = analyzer.encode_frame(result["frame"])

            # 发送结果（不发送原始帧数据，节省带宽）
            await websocket.send_json({
                "type": "result",
                "frame": annotated_b64,
                "stats": result["stats"],
                "detections": result["detections"],
                "timestamp": time.time(),
            })

    except WebSocketDisconnect:
        pass
    except Exception as e:
        try:
            await websocket.send_json({"type": "error", "message": str(e)})
        except Exception:
            pass


@app.websocket("/ws/camera")
async def websocket_camera(websocket: WebSocket):
    """
    WebSocket 摄像头实时分析
    客户端发送: 控制指令 (start/stop/config)
    服务端返回: 实时分析结果流
    """
    await websocket.accept()
    analyzer = RealtimeAnalyzer()
    running = False
    cap = None

    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)

            if msg.get("type") == "start":
                source = msg.get("source", 0)
                # 安全校验：只允许整数摄像头索引（0-10），禁止传入文件路径
                if isinstance(source, str):
                    try:
                        source = int(source)
                    except (ValueError, TypeError):
                        await websocket.send_json({"type": "error", "message": "Invalid camera source"})
                        continue
                if not isinstance(source, int) or source < 0 or source > 10:
                    await websocket.send_json({"type": "error", "message": "Camera source must be 0-10"})
                    continue
                cap = cv2.VideoCapture(source)
                if not cap.isOpened():
                    await websocket.send_json({"type": "error", "message": f"Cannot open camera: {source}"})
                    continue

                running = True
                analyzer.reset()
                await websocket.send_json({"type": "started", "source": source})

                # 逐帧读取并分析
                while running:
                    ret, frame = cap.read()
                    if not ret:
                        break

                    result = analyzer.process_frame(frame)
                    annotated_b64 = analyzer.encode_frame(result["frame"])

                    await websocket.send_json({
                        "type": "result",
                        "frame": annotated_b64,
                        "stats": result["stats"],
                        "detections": result["detections"],
                    })

                    # 检查是否有控制消息（非阻塞）
                    try:
                        ctrl = await asyncio.wait_for(
                            websocket.receive_text(), timeout=0.001
                        )
                        ctrl_msg = json.loads(ctrl)
                        if ctrl_msg.get("type") == "stop":
                            running = False
                            break
                    except asyncio.TimeoutError:
                        pass

                cap.release()
                cap = None
                await websocket.send_json({"type": "stopped"})

            elif msg.get("type") == "stop":
                running = False
                if cap:
                    cap.release()
                    cap = None

            elif msg.get("type") == "config":
                # 动态更新配置
                if "skip_frames" in msg:
                    analyzer.config.target_fps = msg["skip_frames"]
                if "jpeg_quality" in msg:
                    analyzer.config.jpeg_quality = msg["jpeg_quality"]
                await websocket.send_json({"type": "config_updated"})

    except WebSocketDisconnect:
        running = False
        if cap:
            cap.release()
    except Exception as e:
        running = False
        if cap:
            cap.release()
        try:
            await websocket.send_json({"type": "error", "message": str(e)})
        except Exception:
            pass


# Serve frontend static files (production mode)
frontend_dist = Path(__file__).parent.parent / "frontend" / "dist"
if frontend_dist.exists():
    app.mount("/assets", StaticFiles(directory=str(frontend_dist / "assets")), name="static-assets")

    @app.get("/{full_path:path}")
    async def serve_frontend(full_path: str):
        """Serve frontend files (SPA fallback)"""
        file_path = frontend_dist / full_path
        if file_path.is_file():
            return FileResponse(str(file_path))
        return FileResponse(str(frontend_dist / "index.html"))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
