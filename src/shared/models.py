from dataclasses import dataclass
from typing import List, Optional

@dataclass
class OrderItem:
    sku: str
    quantity: int
    price: float

@dataclass
class ShippingAddress:
    city: str
    country: str

@dataclass
class Order:
    customerId: str
    items: List[OrderItem]
    shippingAddress: ShippingAddress
    orderId: Optional[str] = None
