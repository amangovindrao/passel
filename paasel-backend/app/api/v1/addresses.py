"""Address CRUD for customers."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Body
from pydantic import BaseModel
from sqlalchemy import select

from app.api.dependencies import DbSession, require_role
from app.core.errors import AppError
from app.domain.enums import UserRole
from app.models.entities import Address, User

router = APIRouter(prefix="/api/v1/addresses", tags=["addresses"])


class AddressCreate(BaseModel):
    label: str
    lat: float
    lng: float
    address_text: str


class AddressUpdate(BaseModel):
    label: str | None = None
    lat: float | None = None
    lng: float | None = None
    address_text: str | None = None


@router.get("")
async def list_addresses(
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
) -> list[dict]:
    """List the caller's saved addresses."""
    result = await db.execute(
        select(Address).where(Address.customer_id == user.id)
        .order_by(Address.created_at.desc())
    )
    addresses = result.scalars().all()
    return [
        {
            "id": str(a.id),
            "label": a.label,
            "address_text": a.address_text,
            "created_at": a.created_at.isoformat() if a.created_at else None,
        }
        for a in addresses
    ]


@router.post("")
async def create_address(
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: AddressCreate = Body(...),
) -> dict:
    """Create a new saved address."""
    wkt = f"SRID=4326;POINT({body.lng} {body.lat})"
    address = Address(
        customer_id=user.id,
        label=body.label,
        location=wkt,
        address_text=body.address_text,
    )
    db.add(address)
    await db.commit()
    await db.refresh(address)
    return {
        "id": str(address.id),
        "label": address.label,
        "address_text": address.address_text,
    }


@router.patch("/{address_id}")
async def update_address(
    address_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
    body: AddressUpdate = Body(...),
) -> dict:
    """Edit a saved address."""
    address = await db.get(Address, address_id)
    if not address or address.customer_id != user.id:
        raise AppError(404, "not_found", "Address not found")

    if body.label is not None:
        address.label = body.label
    if body.address_text is not None:
        address.address_text = body.address_text
    if body.lat is not None and body.lng is not None:
        address.location = f"SRID=4326;POINT({body.lng} {body.lat})"

    await db.commit()
    return {"id": str(address.id), "label": address.label, "address_text": address.address_text}


@router.delete("/{address_id}")
async def delete_address(
    address_id: UUID,
    user: Annotated[User, require_role(UserRole.CUSTOMER)],
    db: DbSession,
) -> dict:
    """Delete a saved address."""
    address = await db.get(Address, address_id)
    if not address or address.customer_id != user.id:
        raise AppError(404, "not_found", "Address not found")
    await db.delete(address)
    await db.commit()
    return {"status": "deleted"}
