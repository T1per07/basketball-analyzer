"""企业级日志系统 - 结构化日志、性能监控、错误追踪"""
import logging
import json
import time
import functools
from pathlib import Path
from datetime import datetime
from typing import Any, Callable
from contextlib import contextmanager


class StructuredLogger:
    """结构化日志器"""

    def __init__(self, name: str, log_dir: str = None):
        self.name = name
        self.logger = logging.getLogger(name)
        self.logger.setLevel(logging.DEBUG)

        # 控制台处理器
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        console_format = logging.Formatter(
            '%(asctime)s [%(levelname)s] %(name)s: %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        console_handler.setFormatter(console_format)
        self.logger.addHandler(console_handler)

        # 文件处理器（如果指定了目录）
        if log_dir:
            log_path = Path(log_dir)
            log_path.mkdir(parents=True, exist_ok=True)

            file_handler = logging.FileHandler(
                log_path / f"{name}_{datetime.now().strftime('%Y%m%d')}.log",
                encoding='utf-8'
            )
            file_handler.setLevel(logging.DEBUG)
            file_format = logging.Formatter(
                '%(asctime)s [%(levelname)s] %(name)s:%(lineno)d: %(message)s'
            )
            file_handler.setFormatter(file_format)
            self.logger.addHandler(file_handler)

    def _log(self, level: str, message: str, **kwargs):
        """结构化日志"""
        extra = {
            'timestamp': datetime.now().isoformat(),
            'logger': self.name,
            **kwargs
        }
        getattr(self.logger, level)(f"{message} | {json.dumps(extra, ensure_ascii=False)}")

    def info(self, message: str, **kwargs):
        self._log('info', message, **kwargs)

    def debug(self, message: str, **kwargs):
        self._log('debug', message, **kwargs)

    def warning(self, message: str, **kwargs):
        self._log('warning', message, **kwargs)

    def error(self, message: str, **kwargs):
        self._log('error', message, **kwargs)

    def critical(self, message: str, **kwargs):
        self._log('critical', message, **kwargs)


class PerformanceMonitor:
    """性能监控器"""

    def __init__(self):
        self.metrics = {}

    @contextmanager
    def measure(self, name: str):
        """测量代码块执行时间"""
        start = time.perf_counter()
        yield
        elapsed = time.perf_counter() - start

        if name not in self.metrics:
            self.metrics[name] = {
                'count': 0,
                'total_time': 0,
                'min_time': float('inf'),
                'max_time': 0,
                'times': []
            }

        self.metrics[name]['count'] += 1
        self.metrics[name]['total_time'] += elapsed
        self.metrics[name]['min_time'] = min(self.metrics[name]['min_time'], elapsed)
        self.metrics[name]['max_time'] = max(self.metrics[name]['max_time'], elapsed)
        self.metrics[name]['times'].append(elapsed)

        # 保留最近 1000 个样本
        if len(self.metrics[name]['times']) > 1000:
            self.metrics[name]['times'] = self.metrics[name]['times'][-1000:]

    def get_stats(self, name: str) -> dict:
        """获取性能统计"""
        if name not in self.metrics:
            return {}

        m = self.metrics[name]
        times = m['times']

        if not times:
            return {}

        avg_time = m['total_time'] / m['count']
        p95_time = sorted(times)[int(len(times) * 0.95)] if len(times) >= 20 else max(times)

        return {
            'count': m['count'],
            'avg_ms': avg_time * 1000,
            'min_ms': m['min_time'] * 1000,
            'max_ms': m['max_time'] * 1000,
            'p95_ms': p95_time * 1000,
            'fps': 1000 / (avg_time * 1000) if avg_time > 0 else 0
        }

    def get_all_stats(self) -> dict:
        """获取所有性能统计"""
        return {name: self.get_stats(name) for name in self.metrics}

    def reset(self):
        """重置统计"""
        self.metrics.clear()


def performance_decorator(monitor: PerformanceMonitor, name: str = None):
    """性能监控装饰器"""
    def decorator(func: Callable):
        metric_name = name or func.__name__

        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            with monitor.measure(metric_name):
                return func(*args, **kwargs)

        return wrapper
    return decorator


# 全局实例
logger = StructuredLogger('basketball-analyzer', log_dir='logs')
performance_monitor = PerformanceMonitor()


if __name__ == "__main__":
    # 测试日志系统
    logger.info("测试日志", user="test", action="demo")
    logger.error("测试错误", error_code=500, details="Something went wrong")

    # 测试性能监控
    with performance_monitor.measure("test_operation"):
        time.sleep(0.1)

    stats = performance_monitor.get_stats("test_operation")
    print(f"性能统计: {stats}")
