# Simulación tosca del balance: un jugador que compra siempre lo más barato disponible.
# Sirve para ver cuánto tarda cada capa. Los números están copiados de Config.luau / Stats.luau:
# si cambias aquellos, cambia estos.
#   python tools/sim.py [fracción de tiempo jugando activo, por defecto 0.75] [CostScale, por defecto 0.5]
import math
import os
import sys

# SIN=bee,lens python tools/sim.py: simula sin esas mejoras (para ver cuánto mueve cada una)
SIN = set(filter(None, os.environ.get("SIN", "").split(",")))

STAGE = 110
DIG = float(os.environ.get("DIG", 10000))  # Config.DigBase / CostScale
LAYERS = 14  # #Config.Layers
HP0, HPG, VG = 3, 2.92, 1.64
BITE_G, CARRY_G = 1.38, 1.38
# Config.Player y Config.Worker
WALK, BITE_CD, CAPACITY = 12, 0.3, 3
WORKER_BASE = 8
ACTIVE = float(sys.argv[1]) if len(sys.argv) > 1 else 0.75
K = float(sys.argv[2]) if len(sys.argv) > 2 else 0.5  # Config.CostScale


def r2(n):
    if n < 10:
        return max(1, round(n))
    s = 10 ** (math.floor(math.log10(n)) - 1)
    return round(n / s) * s


# FOOD_LIST de Config: tres por zona. Índices (desde 0) de las duras; la última es la tarta.
FOOD_IDS = [
    "Miga", "Semilla", "Arandano", "Galleta", "Sandwich", "Manzana", "Fresa", "Tomate", "Zanahoria",
    "Uvas", "Platano", "Coco", "Patatas", "Helado", "Sandia", "Mazorca", "Brocheta", "Costillas",
    "Azucar", "Huevo", "Queso", "Cereales", "Pan", "Miel", "Yogur", "Sushi", "Lata",
    "Ganchitos", "Zumo", "Sorpresa", "Cruasan", "Barrita", "Nuez", "Palomita", "HotDog", "Hamburguesa",
    "Donut", "Cupcake", "Chocolate", "Gominola", "Pizza", "Tarta",
]
HARD = {5, 8, 11, 14, 17, 23, 26, 29, 32, 38}
BOSS = len(FOOD_IDS) - 1
LOBBY_COUNTS, LOBBY_RESPAWNS = [110, 40, 22], [1.5, 3, 5]
foods = []
for i in range(len(FOOD_IDS)):
    z = i // 3 + 1
    slot = i % 3
    hp = r2(HP0 * HPG**i)
    if i == BOSS:
        hp *= 20
    foods.append(
        dict(
            z=z,
            hp=hp,
            v=r2(VG**i),
            hard=i in HARD,
            count=[12, 7, 5][slot] if z > 1 else LOBBY_COUNTS[slot],
            resp=[5, 9, 14][slot] if z > 1 else LOBBY_RESPAWNS[slot],
            boss=i == BOSS,
        )
    )


# Geometría (Config.Map / Config.Zones): hormigueros en un arco de radio HILL_ARC dentro de un jardín
# de radio LOBBY; la zona 2 empieza en z0 = -(LOBBY + 10) y cada zona ocupa 170 studs (150 de suelo).
LOBBY, HILL_ARC = 150, 122
# Distancia media del hormiguero a las seis comidas del jardín más cercanas (Monte Carlo): unos
# 50 studs con la comida repartida por igual en todo el jardín; 38 desde que la mitad de la del
# jardín sale en la media luna de los hormigueros (FoodService, NEAR_HILLS).
LOBBY_TRIP = 38


def dist(z):
    # Del hormiguero a la mitad de la zona
    return LOBBY_TRIP if z == 1 else HILL_ARC + (LOBBY + 10) + 75 + (z - 2) * 170


# Colonia (Colony.luau): una comida pierde como mucho su vida cada BITE_TIME segundos, y sin rastros
# las obreras trabajan en AUTO_TARGETS comidas del jardín a la vez.
BITE_TIME = 3
AUTO_TARGETS = 3

# Abeja mensajera (Config.Allies.Bee): vuela a SPEED + SPEED_STEP por nivel; vuelve a por carga cada
# INTERVAL s (STEP menos por nivel, nunca menos de MIN) y, desde el nivel FULL, en cuanto te llenas.
def env(name, default):
    return float(os.environ.get(name, default))
BEE_SPEED, BEE_SPEED_STEP = env("BEE_SPEED", 14), env("BEE_SPEED_STEP", 3)
BEE_INTERVAL, BEE_STEP, BEE_MIN, BEE_FULL = env("BEE_INTERVAL", 45), env("BEE_STEP", 6.6), env("BEE_MIN", 12), env("BEE_FULL", 4)


# id: (capa, máximo, niveles por capa, costo a escala de capa 1, crecimiento)
N = dict(
    bite=(1, 140, 10, 10, 1.6), chew=(1, 28, 2, 80, 10.5), crit=(2, 5, 0, 30, 3.5), saw=(2, 1, 0, 300, 1),
    combo=(3, 5, 0, 40, 5), reach=(4, 4, 0, 40, 6), area=(5, 3, 0, 40, 8), brutal=(6, 5, 0, 40, 5),
    venom=(7, 5, 0, 40, 5), titan=(8, 5, 0, 50, 8),
    speed=(1, 42, 3, 24, 4.8), carry=(1, 140, 10, 10, 1.6), sprint=(2, 1, 0, 45, 1), stamina=(2, 5, 0, 70, 4),
    wings=(3, 1, 0, 170, 1), landing=(4, 5, 0, 45, 4), fullLoad=(5, 5, 0, 40, 5), giant=(7, 3, 0, 60, 30),
    double=(9, 5, 0, 40, 5),
    nursery=(1, 28, 2, 36, 10.5), workerCarry=(2, 52, 4, 200, 3.24), workerSpeed=(2, 12, 2, 35, 10.5),
    nurse=(3, 5, 0, 55, 4), storage=(3, 5, 0, 50, 9), barracks=(4, 5, 0, 60, 12), eggs=(4, 5, 0, 40, 6),
    queen=(5, 1, 0, 70, 1), fungus=(6, 5, 0, 50, 6), legion=(7, 10, 0, 45, 4), super=(9, 5, 0, 50, 6),
    sweet=(2, 5, 0, 70, 5), frenzy=(3, 1, 0, 120, 1), frenzyLen=(4, 5, 0, 60, 5), smart=(5, 1, 0, 100, 1),
    express=(6, 5, 0, 40, 5), hive=(8, 5, 0, 40, 5), royalPher=(10, 3, 0, 40, 10),
    # Aliadas (Config.Allies): un nivel más por capa desde la suya
    bee=(2, 6, 1, 60, 100), magnet=(3, 5, 1, 50, 100), beetle=(4, 5, 1, 50, 100), escort=(5, 5, 1, 50, 100),
    stomp=(6, 5, 1, 60, 100), sling=(7, 5, 1, 60, 100), lens=(9, 5, 1, 50, 100), mega=(11, 4, 1, 60, 100),
)
CAPS = [5, 10, 20, 35, 60, 100, 150, 220, 300, 400, 500, 620, 750, 900, 1050, 1200, 1400, 1600, 1800, 2000,
        2200, 2400, 2600, 2800, 3000, 3200, 3400, 3600]
TRAIL = [500, 6e6, 8e12]

# Galerías (Config.MiniTune). Cada capa, 9 por rama; dentro de una fila cada una pide la anterior.
# Se compran como el resto: la más barata primero. Los efectos se suman por tipo (ver Stats.derive).
MINI_SPAN = (15, 600)
MINI_ROT = 4
GOLD_CAP, GOLD_MULT = 0.2, 10
ZONE_BY_LAYER = [0.15, 0.3, 0.1] + [0.05] * (LAYERS - 3)  # Paladar, por capa
BRANCH_COST = dict(M=1, P=1.1, C=1.2, F=0.9)
AMOUNT = dict(
    bitePct=0.08, chewPct=0.03, critPct=0.01, hardPct=0.15, zonePct=0, goldPct=0.002,
    speedPct=0.03, carryPct=0.02, depositPct=0.02,
    workerPct=0.03, capPlus=2, cheapPct=0.04, eggPct=0.1, offlinePct=0.1,
    trailPct=0.03, frenzyPct=0.03, jellyPct=0.02, foodPct=0.01,
)
POOLS = dict(
    M=["bitePct", "chewPct", "zonePct", "critPct", "bitePct", "hardPct", "goldPct", "bitePct", "zonePct"],
    P=["carryPct", "zonePct", "speedPct", "zonePct", "carryPct", "zonePct", "depositPct", "zonePct", "zonePct"],
    C=["workerPct", "capPlus", "cheapPct", "eggPct", "workerPct", "offlinePct", "capPlus", "eggPct", "cheapPct"],
    F=["foodPct", "trailPct", "jellyPct", "frenzyPct", "goldPct", "trailPct", "jellyPct", "frenzyPct", "jellyPct"],
)
minis = []
for layer in range(1, LAYERS + 1):
    for b in "MPCF":
        for slot in range(1, 10):
            kind = POOLS[b][(slot - 1 + (layer - 1) * MINI_ROT) % 9]
            amount = ZONE_BY_LAYER[layer - 1] if kind == "zonePct" else AMOUNT[kind] * (layer if kind == "capPlus" else 1)
            c = MINI_SPAN[0] * (MINI_SPAN[1] / MINI_SPAN[0]) ** ((slot - 1) / 8) * BRANCH_COST[b]
            minis.append(dict(
                id=f"m{b}{layer}_{slot}", L=layer, kind=kind, amount=amount,
                cost=r2(c * STAGE ** (layer - 1) * K),
                prev=None if (slot - 1) % 3 == 0 else f"m{b}{layer}_{slot - 1}",
            ))
owned = set()
T = {k: 0.0 for k in AMOUNT}
ZONE = [0.0] * (LAYERS + 1)
cheap = 1.0

L = {k: 0 for k in N}
L["trail"] = 0
depth = 1
workers = 0
food = 0.0
t = 0.0
run = 0.0


def cost(k):
    lay, mx, per, c, g = N[k]
    return K * c * STAGE ** (lay - 1) * g ** L[k]


def avail(k):
    lay, mx, per, c, g = N[k]
    if depth < lay or k in SIN:
        return 0
    return min(mx, per * (depth - lay + 1)) if per else mx


def income():
    dmg = math.ceil(math.ceil(BITE_G ** L["bite"]) * 2 ** L["titan"] * (1 + T["bitePct"]))
    cd = BITE_CD * 0.95 ** L["chew"] / (1 + T["chewPct"])
    # Escarabajo de carga: +40 % de carga por nivel
    cap = math.floor(CAPACITY * CARRY_G ** L["carry"] * 3 ** L["giant"] * (1 + T["carryPct"]) * (1 + 0.4 * L["beetle"]))
    sp = (WALK + L["speed"]) * (1 + T["speedPct"])
    sp *= 1.35  # correr viene de serie (Config.Run.Mult)
    if L["sprint"]:
        sp *= 1 + (2.3 / 1.35 - 1) * (3 + L["stamina"]) / 12.0  # turbo
    crit = 1 + (0.08 * L["crit"] + T["critPct"]) * (2 + L["brutal"])
    combo = 1 + 0.03 * 10 * L["combo"] * 0.7
    gold = 1 + min(GOLD_CAP, T["goldPct"]) * (GOLD_MULT - 1)
    best = 0
    bf = None
    for f in foods:
        if f["z"] > depth or (f["hard"] and not L["saw"]):
            continue
        d = dmg * crit * combo * ((1 + 0.5 * L["venom"]) * (1 + T["hardPct"]) if f["hard"] else 1)
        items = min(6, f["count"])
        load = min(cap, items * f["hp"])
        n = math.ceil(load / f["hp"])
        # Trozos por segundo mordiendo: tus mordiscos, la escolta (30 % de tu mordida por soldado
        # cada 0,7 s), el mega crunch (un mordisco gigante cada `every`), el pisotón (3 mordiscos a
        # unas dos comidas, cuando está listo) y el imán (tosco: +3 % por nivel)
        rate = min(d, f["hp"]) / cd
        if L["escort"]:
            rate += min(0.3 * L["escort"] * dmg, f["hp"]) / 0.7
        if L["mega"]:
            rate += min((10 + 5 * (L["mega"] - 1)) * d, load) / ((25 - 3 * (L["mega"] - 1)) * cd)
        if L["stomp"]:
            rate += min(6 * dmg, load) / (30 - 4 * (L["stomp"] - 1)) * ACTIVE
        rate *= 1 + 0.03 * L["magnet"]
        work = load / rate + n * 1.2 + 2
        walk = 2 * dist(f["z"]) / sp
        if L["wings"] and f["z"] > 1:
            walk -= dist(f["z"]) / sp * 0.8
        # Abeja y tirachinas: cada viaje que hacen ellas es un paseo que te ahorras
        covered = 0
        if L["bee"]:
            # No vuelve a por otra carga hasta que regresa de casa
            trip = 2 * max(dist(f["z"]) / (BEE_SPEED + BEE_SPEED_STEP * (L["bee"] - 1)), 1.6) + 0.75
            wait = trip if L["bee"] >= BEE_FULL else max(trip, max(BEE_MIN, round(BEE_INTERVAL - BEE_STEP * (L["bee"] - 1))))
            covered = (work + walk) / wait
        if L["sling"] and dist(f["z"]) <= 400 + 200 * (L["sling"] - 1):
            covered += (work + walk) / (40 - 5 * (L["sling"] - 1)) * ACTIVE
        tm = work + walk * (1 - min(covered, 1))
        inc = load * f["v"] * (1 + ZONE[f["z"]]) * gold * (1 + T["depositPct"])
        inc *= (1 + 0.1 * L["fullLoad"]) * (1 + 0.1 * L["double"]) / tm
        # Lupa: quema (4 + 2 por nivel) mordiscos de la comida grande cada (20 - 2 por nivel) s, directo a casa
        if L["lens"]:
            inc += min((4 + 2 * (L["lens"] - 1)) * dmg, f["hp"]) * f["v"] * (1 + ZONE[f["z"]]) / (20 - 2 * (L["lens"] - 1))
        if f["boss"]:
            inc *= 0.5
        if inc > best:
            best = inc
            bf = f
    hand = best * ACTIVE
    col = 0
    if workers > 0:
        wc = 1.6 ** L["workerCarry"] * 2 ** L["super"]
        ws = 8 * (1 + 0.2 * L["workerSpeed"])
        mult = 1.5 ** L["barracks"] * 1.4 ** L["legion"] * (1 + T["workerPct"])
        mult *= (1 + 0.2 * L["sweet"]) * (1 + T["trailPct"])
        if L["frenzy"]:
            fm = (3 + L["royalPher"]) * (1 + T["frenzyPct"])
            mult *= 1 + (fm - 1) * (15 + 5 * L["frenzyLen"]) / (90 - 12 * L["hive"]) * ACTIVE
        for f in foods:
            if f["z"] > depth or (f["hard"] and not L["barracks"]) or f["boss"]:
                continue
            if f["z"] > 1 and L["trail"] == 0:
                continue
            trip = (2 * dist(f["z"]) / ws + 1.5) * 0.88 ** L["express"]
            rate = workers * wc / trip * mult
            # Cuántas comidas a la vez: tres en el jardín sin rastros, un rastro por comida fuera.
            # Cada una cae como pronto en BITE_TIME s y tarda resp en volver.
            targets = AUTO_TARGETS if f["z"] == 1 else L["trail"]
            supply = min(targets * f["hp"] / BITE_TIME, f["count"] * f["hp"] / (BITE_TIME + f["resp"]))
            col = max(col, min(rate, supply) * f["v"] * (1 + ZONE[f["z"]]))
    fm = 1 + T["foodPct"]
    return (hand + col) * fm, hand * fm, col * fm, bf


marks = []
bought_minis = 0
first_buy = None
first_worker = None
while depth < LAYERS or L["bite"] < N["bite"][1] or len(owned) < len(minis):
    opts = []
    for k in N:
        if L[k] < avail(k):
            if k in ("workerCarry", "workerSpeed") and workers == 0:
                continue
            opts.append((cost(k), k))
    if L["trail"] < 3 and workers > 0:
        opts.append((K * TRAIL[L["trail"]], "trail"))
    cap = CAPS[L["nursery"] - 1] + T["capPlus"] if L["nursery"] else 0
    if workers < cap:
        opts.append((WORKER_BASE * 1.03**workers * 0.92 ** L["nurse"] * cheap, "worker"))
    if depth < LAYERS:
        opts.append((K * DIG * STAGE ** (depth - 1), "dig"))
    for i, m in enumerate(minis):
        if m["id"] not in owned and m["L"] <= depth and (m["prev"] is None or m["prev"] in owned):
            opts.append((m["cost"], i))
    if not opts:
        break
    c, k = min(opts, key=lambda o: o[0])
    inc, hand, col, bf = income()
    if food < c:
        dt = (c - food) / inc
        t += dt
        food = c
        run += inc * dt
    food -= c
    if first_buy is None:
        first_buy = (t, k)
    if k == "worker":
        workers += 1
        if first_worker is None:
            first_worker = t
    elif k == "dig":
        depth += 1
        marks.append((depth, t, inc, hand, col, run, bought_minis))
    elif isinstance(k, int):
        m = minis[k]
        owned.add(m["id"])
        bought_minis += 1
        if m["kind"] == "zonePct":
            ZONE[m["L"]] += m["amount"]
        elif m["kind"] == "cheapPct":
            cheap *= 1 - m["amount"]
        else:
            T[m["kind"]] += m["amount"]
    else:
        L[k] += 1
    if t > 3600 * 2000:
        break

prev = 0
jm = 1 + T["jellyPct"]
print(f"primera compra: {first_buy[0]:.0f} s ({first_buy[1]})  primera obrera: {first_worker / 60:.1f} min")
for d, tt, inc, hand, col, rn, nm in marks:
    jelly = int(math.log10(max(rn / 1e12, 1)) ** 2)
    print(f"capa {d:2d}: {tt/60:8.1f} min (+{(tt-prev)/60:6.1f})  ingreso {inc:9.3g}/s  mano {hand:9.3g}  colonia {col:9.3g}  galerías {nm:3d}  jalea {jelly}")
    prev = tt
inc, hand, col, bf = income()
print(f"todo comprado: {t/3600:.1f} h  ingreso {inc:.3g}/s  colonia {col:.3g}  obreras {workers}  galerías {len(owned)}")
dmg = math.ceil(BITE_G ** L["bite"]) * 2 ** L["titan"]
print("tarta hp", foods[BOSS]["hp"], "valor", foods[BOSS]["v"], "mordida", dmg, "carga", math.floor(CAPACITY * CARRY_G ** L["carry"] * 3 ** L["giant"]))
print("galerías al final: " + ", ".join(f"{k} {v:.3g}" for k, v in T.items() if v) + f", obreras x{cheap:.2f}")
