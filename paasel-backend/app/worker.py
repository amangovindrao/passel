"""Celery workers — assignment timeouts, hold-timeouts, settlements."""

from celery import Celery

from app.core.config import settings

celery_app = Celery("paasel", broker=settings.redis_url, backend=settings.redis_url)
celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
    task_acks_late=True,
    task_reject_on_worker_lost=True,
    broker_connection_retry_on_startup=True,
    imports=("app.workers.tasks",),
)

# Periodic jobs. Run with: celery -A app.worker.celery_app beat
celery_app.conf.beat_schedule = {
    "stale-online-sweep": {
        "task": "paasel.stale_online_sweep",
        "schedule": 300.0,  # every 5 minutes
    },
}


@celery_app.task(name="paasel.healthcheck")
def healthcheck() -> dict[str, str]:
    """Smoke test task to verify Celery/Redis connectivity."""
    return {"status": "ok"}


# Phase 3 tasks:
# - paasel.assignment_timeout
# - paasel.hold_timeout
# - paasel.subscription_renewal
# - paasel.settlement_run
