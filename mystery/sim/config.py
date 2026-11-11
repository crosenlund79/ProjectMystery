"""Profiles and tuning. Changing anything here changes histories: bump CONFIG_VERSION."""

from __future__ import annotations

from dataclasses import asdict, dataclass

from mystery import CONFIG_VERSION, SIM_VERSION


@dataclass(frozen=True)
class Profile:
    name: str
    description: str
    wage_mult: float = 1.0
    food_price: int = 4
    delivery_units: int = 150
    initial_debt_rate: float = 0.25
    grudge_pairs: int = 1
    drink_mult: float = 1.0
    impulsive_shift: float = 0.0
    layoffs: int = 0
    mill_margin: int = 45  # the mill's daily profit over the wages it pays
    odd_jobs: float = 0.8  # chance a day's casual work is available at the mill


PROFILES: dict[str, Profile] = {
    "normal": Profile("normal", "An ordinary autumn with modest margins."),
    "scarcity": Profile(
        "scarcity",
        "Supply shortages: food is dear and deliveries arrive short.",
        food_price=6,
        delivery_units=55,
    ),
    "crisis": Profile(
        "crisis",
        "Economic downturn: wages cut, a mill hand laid off, more people in debt.",
        wage_mult=0.7,
        initial_debt_rate=0.5,
        layoffs=1,
        mill_margin=-5,
        odd_jobs=0.3,
    ),
    "tension": Profile(
        "tension",
        "Old grudges, heavy drinking and short tempers.",
        grudge_pairs=3,
        drink_mult=1.5,
        impulsive_shift=0.12,
    ),
}

# Prices and amounts, in crowns.
DRINK_PRICE = 3
DRINK_COST = 1
PUB_MEAL_PRICE = 9
PUB_MEAL_COST = 4
RENT = 40
PENSION_WEEKLY = 110
TILL_FLOAT = {"grocery": 250, "pub": 60}
ODD_JOB_PAY = 12
SUPPLIER_COST_RATIO = 0.6
STOCK_CAPACITY = 220


@dataclass(frozen=True)
class SimConfig:
    seed: int
    days: int = 60
    profile: str = "normal"
    residents: int = 10

    def __post_init__(self) -> None:
        if self.profile not in PROFILES:
            raise ValueError(f"unknown profile {self.profile!r}; choose from {sorted(PROFILES)}")
        if not 8 <= self.residents <= 12:
            raise ValueError("residents must be between 8 and 12 for this prototype")
        if self.days < 1:
            raise ValueError("days must be positive")

    def describe(self) -> dict:
        return {**asdict(self), "sim_version": SIM_VERSION, "config_version": CONFIG_VERSION}
