"""PostgreSQL persistence for user finance records."""

from __future__ import annotations

import os
from datetime import datetime, timezone

from sqlalchemy import DateTime, String, create_engine, delete, select
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.engine import URL
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker


def _database_url() -> str | URL:
    value = os.getenv("DATABASE_URL")
    if value:
        return value
    return URL.create(
        "postgresql+psycopg",
        username=os.getenv("POSTGRES_USER", "wealthsync"),
        password=os.getenv("POSTGRES_PASSWORD", "wealthsync_dev"),
        host=os.getenv("POSTGRES_HOST", "127.0.0.1"),
        port=int(os.getenv("POSTGRES_PORT", "5432")),
        database=os.getenv("POSTGRES_DB", "wealthsync"),
    )


class Base(DeclarativeBase):
    pass


class FinanceRecord(Base):
    """Typed resource documents stored as JSONB, keyed by user/resource/id."""

    __tablename__ = "finance_records"

    user_id: Mapped[str] = mapped_column(String(120), primary_key=True)
    resource: Mapped[str] = mapped_column(String(40), primary_key=True)
    record_id: Mapped[str] = mapped_column(String(120), primary_key=True)
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )


engine = create_engine(
    _database_url(),
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=5,
    connect_args={"connect_timeout": 3},
)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)
ALLOWED_RESOURCES = {"transactions", "accounts", "budgets", "goals", "alerts", "recommendations"}


def initialize() -> None:
    Base.metadata.create_all(engine)


def list_records(user_id: str, resource: str) -> list[dict]:
    with SessionLocal() as session:
        rows = session.scalars(
            select(FinanceRecord)
            .where(FinanceRecord.user_id == user_id, FinanceRecord.resource == resource)
            .order_by(FinanceRecord.updated_at.desc())
        ).all()
        return [row.payload for row in rows]


def save_record(user_id: str, resource: str, record_id: str, payload: dict) -> dict:
    with SessionLocal.begin() as session:
        row = session.get(FinanceRecord, (user_id, resource, record_id))
        if row is None:
            row = FinanceRecord(user_id=user_id, resource=resource, record_id=record_id, payload=payload)
            session.add(row)
        else:
            row.payload = payload
            row.updated_at = datetime.now(timezone.utc)
    return payload


def remove_record(user_id: str, resource: str, record_id: str) -> bool:
    with SessionLocal.begin() as session:
        result = session.execute(
            delete(FinanceRecord).where(
                FinanceRecord.user_id == user_id,
                FinanceRecord.resource == resource,
                FinanceRecord.record_id == record_id,
            )
        )
        return bool(result.rowcount)
