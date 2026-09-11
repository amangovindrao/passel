"""Fail-fast configuration — every required value must be present at startup."""

from functools import lru_cache
from typing import Literal

from pydantic import AnyHttpUrl, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore",
        case_sensitive=False,
        validate_default=True,
    )

    # Required — startup crashes if any of these are absent
    database_url: str
    supabase_url: AnyHttpUrl
    supabase_jwt_secret: str = Field(min_length=32)
    redis_url: str
    razorpay_key_id: str = Field(min_length=1)
    razorpay_key_secret: str = Field(min_length=1)
    sentry_dsn: str = ""
    google_maps_api_key: str = Field(min_length=1)
    environment: Literal["dev", "staging", "prod"] = "dev"

    # Derived / optional
    log_level: str = "INFO"

    @field_validator("database_url")
    @classmethod
    def require_asyncpg(cls, v: str) -> str:
        if not v.startswith("postgresql+asyncpg://"):
            raise ValueError("DATABASE_URL must use the postgresql+asyncpg:// scheme")
        return v

    @property
    def cors_origins(self) -> list[str]:
        if self.environment == "dev":
            return ["*"]
        if self.environment == "staging":
            return [
                "https://staging.paasel.thescaleon.com",
                "https://api.staging.paasel.thescaleon.com",
            ]
        return [
            "https://paasel.thescaleon.com",
            "https://api.paasel.thescaleon.com",
        ]

    @property
    def docs_enabled(self) -> bool:
        return self.environment != "prod"

    @property
    def supabase_issuer(self) -> str:
        return f"{str(self.supabase_url).rstrip('/')}/auth/v1"


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
