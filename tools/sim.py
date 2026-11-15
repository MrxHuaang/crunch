# Simulador del ritmo de CRUNCH!. Copia los números de src/shared/Config.luau y las fórmulas de
# src/shared/Stats.luau: si cambias aquellos, cambia estos.
#
# Simula el bucle de verdad, viaje a viaje: salir del hormiguero, caminar (y correr) hasta los
# racimos de comida de una zona, morder (mordiscos por comida, enfriamiento, cadena y área dentro del
# racimo), llenarse y volver. Encima van la colonia, las ayudantes y el resto (comida dorada, huevos,
# hongos, misiones, sucesos del jardín, apertura guiada, castas y lo social).
#
#   python tools/sim.py                resumen por capa (activo y casual) y verificación de objetivos
#   python tools/sim.py --audit        además, la tabla de cada mejora (ganancia y retorno al abrirse)
#   python tools/sim.py --perfil 0.6   un perfil a medida (fracción del tiempo jugando a mano)
#   SIN=bee,lens python tools/sim.py   sin esas mejoras (para ver cuánto mueve cada una)
import math
import os
import sys

ARGS = sys.argv[1:]
AUDIT = "--audit" in ARGS
SIN = set(filter(None, os.environ.get("SIN", "").split(",")))
VERBOSE = "--detalle" in ARGS


def env(name, default):
    # Cualquier número marcado con env() se puede probar sin tocar el archivo: BITE_POWER=1.3 python tools/sim.py
    return float(os.environ.get(name, default))


# ─────────────────────────── Config.Player / Run / Milestones ───────────────────────────
WALK = env("WALK", 16)             # Config.Player.WalkSpeed
SPEED_STEP = env("SPEED_STEP", 1.2)      # Config.Player.SpeedStep: velocidad por nivel de Paso rápido
RUN = 1.35            # Config.Run.Mult (correr de serie con Shift)
RUN_SHARE = 0.85      # parte del camino que se hace corriendo
BITE_CD = 0.3         # Config.Player.BiteCooldown
MIN_CD = 0.18         # Config.Player.MinBiteCooldown: más rápido que esto, Mordisco veloz da comida
CHEW_STEP = env("CHEW_STEP", 0.88)       # Config.Player.ChewStep: enfriamiento x esto por nivel
BITE_BASE = 3         # Config.Player.BiteBase: trozos del primer mordisco
BITE_POWER = env("BITE_POWER", 1.2)     # Config.Player.BitePower: fuerza de mordida por nivel
BITE_SPLIT = env("BITE_SPLIT", 0.42)     # Config.Player.BiteSplit: parte de la fuerza que es arrancar (el resto, rendir)
CAPACITY = env("CAPACITY", 42)         # Config.Player.Capacity: trozos de carga sin mejoras (14 mordiscos)
CARRY_G = env("CARRY_G", 1.08)       # Config.Player.CarryGrowth: carga por nivel de Lomo fuerte
MIN_LOAD = 12         # Config.Player.MinLoadBites
CRIT_MULT = 3
CRIT_STEP, BRUTAL_STEP, VENOM_STEP = 0.05, 0.5, 0.25
CRIT_CAP = 0.35       # Config.Player.CritCap
NEIGHBOR_CAP = env("NEIGHBOR_CAP", 2.5)  # Config.Player.NeighborCap: área, cadena, doble mandíbula, escolta y mega juntos
MAX_WALK = env("MAX_WALK", 45)
SPEED_YIELD = 0.5
NEIGHBOR_YIELD = 0.5  # Config.Player.NeighborYield: igual con lo que pasa de NeighborCap  # Config.Player.SpeedYield: comida = (velocidad de las mejoras / techo) ^ esto           # Config.Player.MaxWalk: velocidad al andar como mucho; lo que sobra rinde comida
# Mejoras con un extra de comida por nivel (Config.Tree yield / Config.Royal yield): las que solas
# apenas se notaban en el ingreso
NODE_YIELD = dict(carry=0.01, speed=0.01, crit=0.02, workerCarry=0.02, magnet=0.03, stamina=0.05, lane=0.06, landing=0.05, eggs=0.05, giant=0.06, sling=0.05,
                  venom=0.06, giantFood=0.06, rain=0.05, lens=0.05, super=0.05, royalPher=0.08, frenzyLen=0.03, legion=0.03)
ROYAL_YIELD = dict(royalStart=0.05, royalSpeed=0.05, royalDepth=0.06, royalJelly=0.05)
COMBO_TYPICAL = 8     # Config.Combo.Typical: racha media que se cuenta para la carga
AREA_SHARE = 0.5     # Config.Player.AreaShare: parte de la mordida que se lleva cada vecina  # Mordida doble, Mordisco brutal, Saliva ácida por nivel
MS_LEVELS = [10, 25, 50, 75, 100, 125]  # Config.Milestones.Levels
MS_MULT = 2                             # Config.Milestones.Mult
MS_CARRY = env("MS_CARRY", 1.15)         # Config.Milestones.CarryMult: la carga salta menos (si no, los viajes se alargan sin fin)


def ms(level):
    return sum(1 for l in MS_LEVELS if level >= l)


# ─────────────────────────── Etapas, costos ───────────────────────────
STAGE = 110           # Config.StageGrowth
LAYERS = 14
K = float(os.environ.get("K", 7.5))       # Config.CostScale
DIG = float(os.environ.get("DIG", 12000))  # Config.DigBase
WORKER_BASE, WORKER_G = 200, 1.03           # Config.Worker.BaseCost / CostGrowth


def r2(n):
    if n < 10:
        return max(1, round(n))
    s = 10 ** (math.floor(math.log10(n)) - 1)
    return round(n / s) * s


# ─────────────────────────── Comida (Config.FoodCurve) ───────────────────────────
FOOD_IDS = [
    "Miga", "Semilla", "Arandano", "Galleta", "Sandwich", "Manzana", "Fresa", "Tomate", "Zanahoria",
    "Uvas", "Platano", "Coco", "Patatas", "Helado", "Sandia", "Mazorca", "Brocheta", "Costillas",
    "Azucar", "Huevo", "Queso", "Cereales", "Pan", "Miel", "Yogur", "Sushi", "Lata",
    "Ganchitos", "Zumo", "Sorpresa", "Cruasan", "Barrita", "Nuez", "Palomita", "HotDog", "Hamburguesa",
    "Donut", "Cupcake", "Chocolate", "Gominola", "Pizza", "Tarta",
]
HARD = {5, 8, 11, 14, 17, 23, 26, 29, 32, 38}
BOSS = len(FOOD_IDS) - 1
SLOT_BITES = [6, 18, 55]      # Config.FoodCurve.Bites: pulsaciones que cuesta al EMPEZAR su capa
SLOT_VALUE = [1, 1.3, 1.7]    # Config.FoodCurve.SlotValue
# Config.FoodCurve.ZoneValues: lo que vale un trozo de la comida pequeña de cada zona. Ajustado con
# este simulador para que cada capa dure unos 30 min jugando activo (las capas 12 y 13 no abren
# mejoras nuevas: su comida tiene que valer mucho más para no estancarse).
ZONE_VALUES = [1, 2.4, 3.6, 11.6, 26, 45, 560, 1010, 1520, 2640, 7380, 1.01e5, 3.44e5, 5.29e5]  # Config.FoodCurve.ZoneValues (rebajado con los hormigueros de zona)
if os.environ.get("VALUE_FIX"):
    ZONE_VALUES = [v * float(x) for v, x in zip(ZONE_VALUES, os.environ["VALUE_FIX"].split(","))]
BOSS_HP = 20                  # Config.FoodCurve.BossHp (la tarta)
JEFA_HP = 4                   # Config.FoodLayout.JefaHp: la grande del banquete de cada zona
RESPAWN = [2, 4, 7]  # Config.FoodLayout.Respawn: segundos hasta que vuelve cada comida de una zona
# Config.FoodCurve.Extra: lo que pega de más a media capa quien va al día (mordida doble, racha,
# galerías de mordida). Medido con este simulador (--calibrar) y redondeado. HardExtra: la comida dura
# desde la zona HardFrom, donde ya se tiene Saliva ácida.
# Config.FoodCurve.Press: lo que pega de más una pulsación al empezar cada capa (mordida doble, racha y
# galerías de mordida) y HardPress: contra comida dura (Saliva ácida, Quebrantahuesos). Medidos con
# python tools/sim.py --calibrar y redondeados.
PRESS = [float(x) for x in os.environ.get("PRESS", "1,1.3,2.1,2.5,2.5,2.4,3.2,3.6,3.8,3.9,3.7,4,4.2,4.2").split(",")]
HARD_PRESS = [float(x) for x in os.environ.get("HARD_PRESS", "1,1,1.4,1.5,1.5,1.8,1.8,2.8,3.5,4.5,5.1,5.1,7,5.6").split(",")]
EXTRA = [1] * 14
HARD_EXTRA = [1, 1.5, 1.5, 1.6, 1.3, 1.7, 1.7, 2.6, 2.8, 3.6, 4, 3.2, 4, 3.2]  # Config.FoodCurve.HardExtra


def ref_damage(zone):
    # Lo que arranca una pulsación de quien EMPIEZA la capa con lo de la anterior comprado:
    # Mordida fuerte al nivel 10 * (zona - 1) por PRESS (galerías, mordida doble y racha de media)
    lvl = 10 * (zone - 1)
    return BITE_BASE * (BITE_POWER ** lvl * MS_MULT ** ms(lvl)) ** BITE_SPLIT * PRESS[zone - 1]


# Racimos por zona (Config.FoodLayout.Clusters): (veces, pequeñas, medianas, grandes, jefa)
CLUSTERS = [(2, 7, 0, 0, 0), (3, 4, 0, 1, 0), (2, 2, 3, 0, 0), (1, 6, 4, 2, 1)]
PER_ZONE = [sum(c[0] * c[i + 1] for c in CLUSTERS) for i in range(4)]
GARDEN_COUNTS, GARDEN_RESP = [110, 40, 22], [1.5, 3, 5]
foods = []
for i, fid in enumerate(FOOD_IDS):
    z, slot = i // 3 + 1, i % 3
    hp = r2(SLOT_BITES[slot] * ref_damage(z) * (HARD_PRESS[z - 1] if i in HARD else 1))
    v = r2(ZONE_VALUES[z - 1] * SLOT_VALUE[slot])
    count = GARDEN_COUNTS[slot] if z == 1 else PER_ZONE[slot]
    f = dict(id=fid, z=z, slot=slot, hp=hp, v=v, hard=i in HARD, boss=i == BOSS, count=count,
             resp=GARDEN_RESP[slot] if z == 1 else RESPAWN[slot])
    if f["boss"]:
        f.update(hp=hp * BOSS_HP, count=1, resp=45)
    foods.append(f)

# ─────────────────────────── Geometría (Config.Map) ───────────────────────────
LOBBY, HILL_ARC, HILL_FROM, HILL_TO = 150, 122, 12, 168
HALF = 95             # Config.Map.Half
ZONE_GAP = 250        # Config.Map.ZoneGap
ZONE_LEN = 230        # Config.Map.ZoneLength
CLUSTER_IN = 25       # Config.FoodLayout.Margin: los racimos empiezan a esto de la puerta
DEPTH_IN = 60         # cuánto te metes de media en la zona hasta el racimo que te comes
GARDEN_TRIP = 34      # hormiguero -> racimos del jardín (la mitad sale en la media luna)
CLUSTER_HOP = 26      # de un racimo al siguiente
FOOD_HOP = 6          # de una comida a la de al lado dentro del racimo (studs), más 0,25 s de apuntar
FOODS_PER_CLUSTER = 6
COLONY_SPREAD = env("COLONY_SPREAD", 4)  # Config.Colony.Spread: comidas del racimo que se reparten lo que no cabe


def zone_start(zone):
    return 0 if zone == 1 else -(LOBBY + 10 + (zone - 2) * ZONE_GAP)


_hills = [(math.cos(math.radians(HILL_FROM + (HILL_TO - HILL_FROM) * k / 5)) * HILL_ARC,
           math.sin(math.radians(HILL_FROM + (HILL_TO - HILL_FROM) * k / 5)) * HILL_ARC) for k in range(6)]
MOUTH = math.sqrt(LOBBY ** 2 - HALF ** 2)
TO_MOUTH = sum(math.hypot(x, y + MOUTH) for x, y in _hills) / 6


def dist(zone):
    # Del hormiguero al racimo de una zona: hasta la boca del jardín, por el camino y un poco dentro
    if zone == 1:
        return GARDEN_TRIP
    return TO_MOUTH + (-zone_start(zone) - MOUTH) + DEPTH_IN


# Hormigueros de zona (Config.Depot / Config.depotPos): a la derecha del camino, ZIn dentro de la puerta.
# Fuera del jardín se entrega ahí, a mano y las obreras.
DEPOT_X = HALF - 20   # Config.Depot.X
DEPOT_IN = 12         # Config.Depot.ZIn
LAST_ZONE_LEN = 320   # Config.Map.LastZoneLength


def depot_trip(zone):
    """Distancia plana media del hormiguero de zona a los centros de la rejilla 3x3 de racimos
    (misma geometría que FoodService: x en [-Half+14, Half-14], z de z0-25 a z1+16; en la 14, z1+95)."""
    z0 = zone_start(zone)
    z1 = z0 - (LAST_ZONE_LEN if zone == 14 else ZONE_LEN)
    x0, x1 = -HALF + 14, HALF - 14
    z_near = z0 - CLUSTER_IN
    z_far = z1 + (95 if zone == 14 else 16)
    cw, cl = (x1 - x0) / 3, (z_near - z_far) / 3
    dx, dz = DEPOT_X, z0 - DEPOT_IN
    total = 0.0
    for row in range(3):
        for col in range(3):
            cx = x0 + (col + 0.5) * cw
            cz = z_near - (row + 0.5) * cl
            total += math.hypot(cx - dx, cz - dz)
    return total / 9


# ─────────────────────────── Árbol (Config.Tree) ───────────────────────────
# id: (capa, máximo, niveles por capa, costo a escala de capa 1, crecimiento)
N = dict(
    bite=(1, 140, 10, 6, 1.6), chew=(1, 28, 2, 60, 10.5), crit=(2, 5, 0, 30, 3.5), saw=(2, 1, 0, 300, 1),
    combo=(3, 5, 0, 40, 5), reach=(4, 4, 0, 40, 6), area=(5, 3, 0, 40, 8), brutal=(6, 5, 0, 40, 5),
    venom=(8, 5, 0, 40, 5), titan=(8, 5, 0, 50, 8),
    speed=(1, 42, 3, 15, 4.8), carry=(1, 140, 10, 6, 1.6), sprint=(2, 1, 0, 25, 1), stamina=(2, 5, 0, 20, 4),
    wings=(3, 1, 0, 170, 1), landing=(4, 5, 0, 45, 4), fullLoad=(5, 5, 0, 40, 5), giant=(7, 3, 0, 60, 15),
    double=(9, 5, 0, 40, 5),
    nursery=(1, 28, 2, 50, 10.5), workerCarry=(2, 26, 2, 100, 10.5), workerSpeed=(2, 12, 2, 35, 10.5),
    nurse=(3, 5, 0, 55, 4), storage=(3, 5, 0, 50, 9), barracks=(4, 5, 0, 60, 12), eggs=(4, 5, 0, 25, 6),
    queen=(5, 1, 0, 70, 1), fungus=(6, 5, 0, 50, 6), legion=(7, 10, 0, 45, 4), super=(9, 5, 0, 50, 6),
    sweet=(2, 5, 0, 70, 5), frenzy=(3, 1, 0, 120, 1), frenzyLen=(4, 5, 0, 40, 5), smart=(5, 1, 0, 100, 1),
    express=(6, 5, 0, 40, 5), hive=(8, 5, 0, 40, 5), royalPher=(10, 3, 0, 40, 10),
    bee=(2, 6, 1, 60, 100), magnet=(3, 5, 1, 50, 100), beetle=(4, 5, 1, 50, 100), escort=(5, 5, 1, 50, 100),
    stomp=(6, 5, 1, 60, 100), sling=(7, 5, 1, 60, 100), lens=(9, 5, 1, 50, 100), mega=(11, 4, 1, 60, 100),
    goldFood=(2, 5, 0, 60, 4), tunnel=(2, 1, 0, 40, 1), chain=(3, 5, 0, 50, 5),
    charged=(4, 3, 0, 45, 6), doubleJaw=(9, 3, 0, 50, 8), buche=(6, 5, 0, 45, 5),
    lane=(3, 3, 0, 60, 6), giantFood=(7, 3, 0, 50, 8), rain=(8, 5, 1, 60, 100),
)
# Cámara madre de cada nodo (Config.Tree parent); "workers" = hace falta al menos una obrera
PARENT = dict(
    chew="bite", crit="chew", saw="crit", combo="saw", reach="combo", area="reach", brutal="area", venom="brutal",
    titan="venom", chain="combo", charged="reach", doubleJaw="titan",
    carry="speed", sprint="carry", stamina="sprint", wings="stamina", landing="wings", fullLoad="landing",
    giant="fullLoad", tunnel="stamina", buche="fullLoad", double="giant",
    workerSpeed="workers", workerCarry="workerSpeed", storage="workerCarry", nurse="storage", barracks="nurse",
    eggs="barracks", queen="eggs", fungus="queen", legion="fungus", super="legion",
    sweet="trail", frenzy="sweet", frenzyLen="frenzy", smart="frenzyLen", express="smart", goldFood="sweet",
    lane="frenzy", giantFood="express", hive="express", royalPher="hive",
    magnet="bee", beetle="magnet", escort="beetle", stomp="escort", sling="stomp", rain="sling", lens="sling",
    mega="lens",
)
OFFLINE = {"storage"}  # solo rinde sin ti (y abre la rama de la colonia)
# Mejoras que no se miden bien en ingreso: puertas a otras ramas o comodidad de viaje
QOL = dict(storage="fuera de línea + puerta", trail="puerta (rastros a las zonas)", nurse="puerta + cupo",
           reach="comodidad (alcance)", tunnel="viaje (se nota al bajar de zona)", wings="viaje")
TRAIL_COSTS = [1200, 4.5e7, 6e13]   # Config.Tree trail.costs
CAPS = [5, 10, 20, 35, 55, 80, 110, 150, 200, 260, 330, 410, 500, 600, 700, 800, 900, 1000, 1100, 1200,
        1300, 1400, 1500, 1600, 1700, 1800, 1900, 2000]  # Config.NurseryCaps

# Números de mejoras (Config.Allies, Config.Extras, Config.Sprint...)
SPRINT_MULT, SPRINT_DUR, SPRINT_CD = 2.3, 3, 12
STAMINA_STEP = 4   # Resuello: segundos de turbo por nivel
WINGS_CD, WINGS_FLY = 12, 1.4
LANDING_CD, LANDING_SPEED = 1.5, 0.08  # Vuelo corto por nivel: segundos menos de alas y velocidad
GIANT_CARRY = env("GIANT_CARRY", 1.15)          # Config.Tree giant: carga x esto por nivel
BEETLE = env("BEETLE", 0.08)  # Config.Allies.Beetle.Share
BARRACKS = env("BARRACKS", 1.15)  # Config.Colony.Barracks: colonia x esto por nivel de Cuartel
LEGION = env("LEGION", 1.05)      # Config.Colony.Legion: por nivel de Legión
SUPER = env("SUPER", 1.35)
SWEET = env("SWEET", 0.1)
EXPRESS = env("EXPRESS", 0.92)     # Autopista: viaje de las obreras x esto por nivel         # Feromona dulce: la comida marcada rinde esto más por nivel         # Supercolonia: carga de obreras x esto por nivel
TITAN = env("TITAN", 1.3)         # Mandíbula titán: fuerza de mordida x esto por nivel
WORKER_SPEED, WORKER_CARRY, WORKER_TURN = env("WORKER_SPEED", 16), env("WORKER_CARRY", 1), 1.5
WORKER_CARRY_G = env("WORKER_CARRY_G", 1.18)      # Config.Worker.CarryGrowth (Obreras fuertes, por nivel)
BEE = dict(Interval=30, Step=4, Min=10, Full=4, Speed=30, SpeedStep=5)
GOLD_FOOD = (0.02, 0.004, 5, 1.5)   # Chance, ChanceStep, Mult, MultStep
CHAIN_SHARE, CHAIN_FIRST = 0.7, 3  # Config.Chain: el primer salto pega First mordiscos; cada siguiente, Share del anterior
WORKER_SPEED_STEP = env("WORKER_SPEED_STEP", 0.1)   # Obreras rápidas por nivel
NURSE_CAP = 0.15          # Nodrizas: cupo de guardería por nivel
QUEEN_MULT, SMART_MULT = 1.15, 1.25  # la reina y el rastro listo también hacen rendir más a la colonia
MAGNET = dict(Tick=2, Bites=10, Count=1)
ESCORT = dict(Tick=0.5, Share=0.6)
STOMP = dict(Cooldown=20, Step=2, Mult=8)
SLING = dict(Cooldown=40, Step=5, Range=4000, RangeStep=0)
LENS = dict(Interval=20, Step=2, Mult=20, MultStep=8)
MEGA = dict(Every=15, Step=2, Mult=15, MultStep=5)
JAW = (0.6, 0.2)
FRENZY_LEN, FRENZY_HIVE = 8, 15  # Config.Frenzy.LenStep y HiveStep
CHAIN_TYPICAL = 8   # Config.Chain.Typical: mordiscos de una comida típica (para contar la cadena en la carga)
CHARGED = (2.2, 0.6)
RAIN = dict(Cooldown=45, Step=3, Count=16, CountStep=6, Bites=6)
GIANT_FOOD = dict(Interval=60, Step=10, Mult=8, MultStep=2)
TUNNEL_WALK, TUNNEL_TRIP = 15 + DEPTH_IN, 1.2
LANE_TIME = 0.5
CHARGE_USE = 0.3
# Config.Egg (Interval, Seconds, IntervalStep, SecondsStep, MinInterval) y Config.Fungus (Regrow, Duration, Step)
EGG = (300, 15, 15, 4, 210)
EGG_FLOOR = 300   # Config.Egg.FloorBites: como poco, tantos mordiscos a la comida pequeña de tu zona
FUNGUS = (300, 15, 3)
TROPHY = 0.03
BITE_TIME = 3              # Colony: una comida pierde como mucho su vida cada 3 s
AUTO_TARGETS = 3
G_WSTEP, G_WREF, G_MAX, G_RESP_MAX, G_DRAIN = 0.3, 25, 2.4, 2, 0.18
# Apertura guiada (Config.Opening): premios de los pasos antes de la capa 2 y el de la capa 2
OPENING = dict(prizes=[15, 50, 20, 50, 125], dig=7500, juicy=30, juicy_mult=2)
# Misiones (src/server/Quests.luau): EFFORT s de juego; PAY s de ingreso. Tres huecos a la vez.
QUEST_EFFORT, QUEST_PAY = [120, 210, 300], [14, 26, 45]
QUEST_EFFICIENCY = 0.7     # parte del tiempo que de verdad avanza alguna misión
# Sucesos del jardín (Config.Garden.Happen): uno cada ~150 s; el regalo vale 45 s de colonia o 20 mordiscos
GARDEN_EVENT = (150, 30, 20)
# Social (Config.Social): despensa PantryShare de lo entregado a mano (a medias si pacífico), más
# amistad/dúo/regalos (topes del propio bloque). Solo cuenta si juegas con alguien.
SOCIAL_PANTRY, SOCIAL_OTHER = 0.08, 0.03
SOCIAL_ON = os.environ.get("SOCIAL", "1") == "1"
# Castas (Config.Castes.PowerShare): el botín de las habilidades de área va directo al hormiguero al 60 %.
# Tosco: una habilidad cada 20 s que se come ~3 comidas pequeñas de tu zona.
CASTE_SHARE, CASTE_EVERY, CASTE_FOODS = 0.6, 20, 3

# ─────────────────────────── Galerías (Config.MiniTune) ───────────────────────────
MINI_SPAN = (10, 250)
MINI_ROT = 4
MINI_MID = 5
MINI_EARLY = [1.5, 1.5, 1.2]
BRANCH_COST = dict(M=1, P=1.1, C=1.2, F=0.9)
KINDS = dict(
    bite=("bite", 0.08, 0, 0, 1), chew=(None, 0.03, 0, 0, 1), crit=(None, 0.01, 0, 0, 1),
    critHit=(None, 0.08, 0, 0, 1), reach=(None, 0.5, 0, 0, 1), chain=(None, 1, 0, 0, 4),
    carry=("carry", 0.08, 0, 0, 1), speed=(None, 1, 0.1, 0.5, 1), turbo=(None, 0.5, 0, 0, 2),
    deposit=("deposit", 0.25, 0, 0, 1), bee=(None, 1, 0, 0, 2), magnet=(None, 1, 0, 0, 3), wings=(None, 1, 0, 0, 3),
    crew=(None, 1, 1, 0, 1), workerCarry=("worker", 0.15, 0, 0, 1), cheap=(None, 0.04, 0, 0, 1),
    eggTime=(None, 10, 0, 0, 4), eggValue=(None, 4, 0, 0, 4), offline=(None, 15, 0, 0, 3),
    workerSpeed=(None, 0.4, 0, 0, 1), jelly=(None, 0.02, 0, 0, 1), trail=(None, 0.03, 0, 0, 1),
    frenzyLen=(None, 1, 0, 0, 3), frenzyCd=(None, 2, 0, 0, 3), fungus=(None, 2, 0, 0, 6),
)
POOLS = dict(
    M=["bite", "chew", "bite", "crit", "reach", "critHit", "chain"],
    P=["carry", "speed", "deposit", "carry", "turbo", "bee", "magnet", "wings"],
    C=["crew", "workerCarry", "cheap", "workerCarry", "eggTime", "offline", "eggValue"],
    F=["workerSpeed", "jelly", "frenzyLen", "trail", "frenzyCd", "workerSpeed", "fungus"],
)
PERK_ORDER = dict(
    M=["first", "lastBite", "streak", "hungry", "sweep", "palate", "crusher"],
    P=["fullSpeed", "lightSpeed", "depStreak", "starDep", "filler", "pedometer", "loot"],
    C=["star", "pantry", "cradle", "shift", "rush", "fullNest", "wake"],
    F=["early", "nugget", "clover", "pureGold", "party", "fever", "frenzyBite"],
)
PERKS = dict(
    first=(1.5, 0.25), lastBite=(2, 0.25), streak=(20, -2), hungry=(2, 0.5), sweep=(10, -1), palate=(3, 1),
    crusher=(1.5, 0.25), fullSpeed=(4, 1.5), lightSpeed=(4, 1.5), depStreak=(2, 1), starDep=(1.5, 0.1),
    filler=(2, 1), pedometer=(1, 0.5), loot=(2, 1), star=(5, 5), pantry=(0.5, 0.1), cradle=(1, 0.2),
    shift=(1, 0.5), rush=(10, 2), fullNest=(10, 5), wake=(2, 1), early=(1, 0.5), nugget=(250, -25),
    clover=(1, 0.3), pureGold=(12, 1), party=(2, 0.5), fever=(1, 0.2), frenzyBite=(1.5, 0.25),
)
INT_PERKS = {"fever", "cradle"}
DEP_STACKS = 3


def level_damage(bite_lvl):
    return BITE_BASE * (BITE_POWER ** bite_lvl * MS_MULT ** ms(bite_lvl)) ** BITE_SPLIT


def level_capacity(carry_lvl):
    return CAPACITY * CARRY_G ** carry_lvl * MS_CARRY ** ms(carry_lvl)


def worker_carry_at(lvl):
    return WORKER_CARRY * WORKER_CARRY_G ** lvl * MS_MULT ** ms(lvl)


def mini_ref(ref, layer):
    lv = 10 * layer - MINI_MID
    if ref == "bite":
        return level_damage(lv)
    if ref == "carry":
        return level_capacity(lv)
    if ref == "worker":
        return worker_carry_at(2 * layer - 1)
    return level_capacity(lv) * foods[(layer - 1) * 3 + 1]["v"]


minis = []
for layer in range(1, LAYERS + 1):
    for b in "MPCF":
        for slot in range(1, 10):
            row, col = (slot - 1) // 3 + 1, (slot - 1) % 3 + 1
            c = MINI_SPAN[0] * (MINI_SPAN[1] / MINI_SPAN[0]) ** ((slot - 1) / 8) * BRANCH_COST[b]
            m = dict(id=f"m{b}{layer}_{slot}", L=layer, cost=r2(c * STAGE ** (layer - 1) * K),
                     prev=None if col == 1 else f"m{b}{layer}_{slot - 1}")
            if col == 3:
                i = (layer - 1) * 3 + row - 1
                m.update(kind="perk", perk=PERK_ORDER[b][i % 7], amount=1)
            else:
                pool = POOLS[b]
                start = ((row - 1) * 2 + col - 1 + (layer - 1) * MINI_ROT) % len(pool)
                kind = next(pool[(start + k) % len(pool)] for k in range(len(pool))
                            if KINDS[pool[(start + k) % len(pool)]][4] <= layer)
                ref, val, step, rnd, _ = KINDS[kind]
                early = MINI_EARLY[layer - 1] if layer <= len(MINI_EARLY) else 1
                amount = r2(val * mini_ref(ref, layer) * early) if ref else val + step * (layer - 1)
                if rnd:
                    amount = max(rnd, math.floor(amount / rnd + 0.5) * rnd)
                m.update(kind=kind, amount=amount)
            minis.append(m)

ROYAL = dict(royalFood=(20, 1, 1), royalBite=(10, 3, 3), royalColony=(10, 3, 3), royalStart=(10, 2, 2),
             royalSpeed=(5, 2, 1), royalDepth=(7, 4, 4), royalJelly=(10, 2, 2))
REBIRTH_DIV, REBIRTH_POW = 3e12, 2


def jelly_for(run_food, mult=1.0):
    return int(math.log10(max(run_food / REBIRTH_DIV, 1)) ** REBIRTH_POW * mult)


# ═══════════════════════════ Estado y estadísticas ═══════════════════════════
class Game:
    def __init__(self, active, royal=None):
        self.active = active
        self.royal = dict(royal or {})
        self.L = {k: 0 for k in N}
        self.L["trail"] = 0
        self.T = {k: 0.0 for k in KINDS}
        self.T["cup"] = 0.0
        self.PL = {}
        self.cheap = 1.0
        self.owned = set()
        self.depth = 1 + self.royal.get("royalDepth", 0)
        self.workers = 15 * self.royal.get("royalStart", 0)  # Config.Rebirth.StartWorkers
        self.food = 0.0
        self.prized = bool(self.royal)
        self.t = 0.0
        self.run = 0.0

    # Stats.derive
    def pv(self, pid):
        n = self.PL.get(pid, 0)
        if n <= 0:
            return 0
        v = PERKS[pid][0] + PERKS[pid][1] * (n - 1)
        return math.floor(v) if pid in INT_PERKS else v

    def stats(self):
        L, T = self.L, self.T
        rb = self.royal.get("royalBite", 0)
        power = BITE_POWER ** L["bite"] * MS_MULT ** ms(L["bite"]) * TITAN ** L["titan"] * 2 ** rb
        lvl_dmg = BITE_BASE * (BITE_POWER ** L["bite"] * MS_MULT ** ms(L["bite"])) ** BITE_SPLIT
        dmg = round(lvl_dmg + T["bite"])
        dmg = max(dmg, 1)
        cd_raw = BITE_CD * CHEW_STEP ** L["chew"] / (1 + T["chew"])
        cd = max(MIN_CD, cd_raw)
        chew_yield = MIN_CD / cd_raw if cd_raw < MIN_CD else 1
        yield_ = (BITE_POWER ** L["bite"] * MS_MULT ** ms(L["bite"])) ** (1 - BITE_SPLIT) * TITAN ** L["titan"] * 2 ** rb
        yield_ *= chew_yield
        yield_ *= (self.neighbors() / min(self.neighbors(), NEIGHBOR_CAP)) ** NEIGHBOR_YIELD
        for k, y in NODE_YIELD.items():
            yield_ *= (1 + y) ** L[k]
        for k, y in ROYAL_YIELD.items():
            yield_ *= (1 + y) ** self.royal.get(k, 0)
        # La carga crece con todo lo que suba la mordida aparte de Mordida fuerte (galerías, mordida
        # doble media): así comprar mordida nunca deja viajes más cortos
        dmg_ratio = dmg / lvl_dmg * self.harvest()
        own = max(math.floor((level_capacity(L["carry"]) + T["carry"])
                             * dmg_ratio * GIANT_CARRY ** L["giant"]), MIN_LOAD * dmg * self.harvest())
        cap = math.floor(own * (1 + BEETLE * L["beetle"]))
        trophies = min(3 * self.depth, 42)
        food_mult = (1 + 0.5 * self.royal.get("royalFood", 0)) * yield_ * (1 + TROPHY * trophies)
        raw_sp = (WALK + SPEED_STEP * (L["speed"] + T["speed"])) * (1 + 0.15 * self.royal.get("royalSpeed", 0)) * (1 + LANDING_SPEED * L["landing"])
        sp = min(raw_sp, MAX_WALK)
        food_mult *= (raw_sp / sp) ** SPEED_YIELD  # lo que pasa del techo rinde comida (Stats.derive)
        return dict(power=power, dmg=dmg, cd=cd, own=own, cap=cap, food_mult=food_mult, speed=sp, raw_speed=raw_sp,
                    yield_=yield_, lvl_dmg=lvl_dmg)

    def crit_avg(self):
        # Lo que pega de media un mordisco por la mordida doble (Stats.critAverage)
        L, T = self.L, self.T
        chance = min(CRIT_CAP, CRIT_STEP * L["crit"] + T["crit"])
        return 1 + chance * (CRIT_MULT - 1 + BRUTAL_STEP * L["brutal"] + T["critHit"])

    def harvest(self):
        """Stats.harvest: trozos que entran de media por cada mordisco tuyo, en mordiscos normales.
        Mordida doble y racha, por lo que arrancan a las vecinas área, doble mandíbula, cadena, escolta y
        mega crunch (como mucho NEIGHBOR_CAP veces: más allá, en vez de comerse el racimo de golpe,
        rinden comida). La carga se mide en mordiscos: crece con esto."""
        return self.crit_avg() * self.combo_avg() * min(self.neighbors(), NEIGHBOR_CAP)

    def neighbor_scale(self):
        n = self.neighbors()
        return min(n, NEIGHBOR_CAP) / n

    def neighbors(self):
        L, T = self.L, self.T
        h = 1.0
        if L["area"]:
            h *= 1 + AREA_SHARE * min(3, L["area"])
        if L["doubleJaw"]:
            h *= 1 + JAW[0] + JAW[1] * (L["doubleJaw"] - 1)
        if L["chain"]:
            jumps = int(L["chain"] + T["chain"])
            h *= 1 + sum(CHAIN_FIRST * CHAIN_SHARE ** (k - 1) for k in range(1, jumps + 1)) / CHAIN_TYPICAL
        if L["escort"]:
            h *= 1 + ESCORT["Share"] * L["escort"] * BITE_CD / ESCORT["Tick"]
        if L["mega"]:
            h *= 1 + (MEGA["Mult"] + MEGA["MultStep"] * (L["mega"] - 1) - 1) / (MEGA["Every"] - MEGA["Step"] * (L["mega"] - 1))
        return h

    def combo_avg(self):
        # Racha media: se pierde al caminar entre racimos, así que de media no pasa de COMBO_TYPICAL mordiscos
        return 1 + 0.03 * min(10 * self.L["combo"], COMBO_TYPICAL)

    def worker_cap(self):
        return math.floor(CAPS[self.L["nursery"] - 1] * (1 + NURSE_CAP * self.L["nurse"])) + self.T["cup"] if self.L["nursery"] else 0

    def frenzy_share(self):
        L, T = self.L, self.T
        return (20 + FRENZY_LEN * L["frenzyLen"] + T["frenzyLen"]) / max(30, 90 - FRENZY_HIVE * L["hive"] - T["frenzyCd"])

    def gold_food(self, f):
        if f["boss"]:
            return 1
        lv = self.L["goldFood"]
        chance = GOLD_FOOD[0] + GOLD_FOOD[1] * lv
        return 1 + chance * (GOLD_FOOD[2] + GOLD_FOOD[3] * lv - 1)

    def gold_bite(self):
        worth = self.pv("pureGold") or 10
        chance = 1 / self.pv("nugget") * (1 + self.pv("fever")) if self.pv("nugget") else 0
        return 1 + min(1, chance) * (worth - 1)

    # ───────────── El viaje a mano en una zona ─────────────
    def trip(self, st, zone, allies=True, extras=True):
        """Un viaje a una zona comiendo su mezcla de racimos. Devuelve un dict con tiempos y valor."""
        L, T = self.L, self.T
        diet = [f for f in foods if f["z"] == zone and not f["boss"] and (not f["hard"] or L["saw"])]
        if not diet:
            return None
        # Peso de cada comida en la mezcla: cuántas hay (la jefa del banquete cuenta como 4 grandes)
        weights = []
        for f in diet:
            n = f["count"] + (JEFA_HP if f["slot"] == 2 and zone > 1 else 0)
            weights.append(n * f["hp"])
        tot = sum(weights)
        dmg, cd, cap = st["dmg"], st["cd"], st["cap"]
        crit = self.crit_avg()
        combo = self.combo_avg()
        sp = st["speed"] * (1 + (RUN - 1) * RUN_SHARE)
        if L["sprint"]:
            sp *= 1 + (SPRINT_MULT / RUN - 1) * (SPRINT_DUR + STAMINA_STEP * L["stamina"] + T["turbo"]) / SPRINT_CD
        if L["lane"] and L["trail"]:
            sp *= 1 + (0.3 + 0.2 * (L["lane"] - 1)) * LANE_TIME
        bites = foods_eaten = value = 0.0
        bites_per_food = {}
        for f, w in zip(diet, weights):
            share = w / tot
            pieces = cap * share
            hard = ((1 + VENOM_STEP * L["venom"]) * max(1, self.pv("crusher"))) if f["hard"] else 1
            d = dmg * crit * combo * hard
            per_food = max(1, math.ceil(f["hp"] / d))
            # Lo que entra en la carga por mordisco: lo arrancado a la comida mordida (con el sobrante
            # del último) más el área (media mordida a las vecinas del racimo) y la doble mandíbula
            harvest = f["hp"] / per_food
            ns = self.neighbor_scale()
            if L["area"]:
                r = 4 + 3 * L["area"]
                harvest += AREA_SHARE * dmg * hard * min(3, (r / FOOD_HOP) ** 2 * 0.6) * ns
            if L["doubleJaw"]:
                harvest += (JAW[0] + JAW[1] * (L["doubleJaw"] - 1)) * dmg * hard * ns
            # Mordida en cadena: al terminar una comida el rayo salta a las de al lado
            if L["chain"]:
                jumps = L["chain"] + T["chain"]
                chain = sum(min(CHAIN_FIRST * CHAIN_SHARE ** (k - 1) * dmg, f["hp"]) for k in range(1, int(jumps) + 1)) * 0.9
                harvest += chain / per_food * ns
            eaten_here = pieces / f["hp"]
            bites += pieces / harvest
            foods_eaten += eaten_here
            self.mean_crit = crit * combo
            value += pieces * f["v"] * self.gold_food(f) if extras else pieces * f["v"]
            bites_per_food[f["slot"]] = per_food
        # Mordisco cargado: en comida grande parte del tiempo carga y pega Mult veces
        if L["charged"]:
            bites *= 1 - CHARGE_USE + CHARGE_USE / (CHARGED[0] + CHARGED[1] * (L["charged"] - 1))
        # Reglas de mordisco (Primer mordisco, Hambre voraz, Buena racha, Barrido, Frenesí contagioso)
        saved = 0.0
        if self.pv("first"):
            saved += foods_eaten * min(1, self.pv("first") - 1)
        if self.pv("hungry"):
            saved += min(self.pv("hungry"), bites / 2)
        if self.pv("streak"):
            saved += bites * 0.7 / self.pv("streak") * 2
        if self.pv("sweep"):
            saved += bites / self.pv("sweep")
        if L["frenzy"] and self.pv("frenzyBite"):
            saved += bites * (1 - 1 / (1 + (self.pv("frenzyBite") - 1) * self.frenzy_share()))
        bites = max(bites * 0.3, bites - saved)
        # Ayudantes que muerden contigo: escolta, mega crunch, pisotón, imán (bites que te ahorran)
        helper_bites = 0.0
        if allies:
            per_sec = 0.0
            if L["escort"]:
                per_sec += ESCORT["Share"] * L["escort"] * dmg / ESCORT["Tick"] * self.neighbor_scale()
            if L["mega"]:
                per_sec += (MEGA["Mult"] + MEGA["MultStep"] * (L["mega"] - 1)) * dmg / ((MEGA["Every"] - MEGA["Step"] * (L["mega"] - 1)) * cd) * self.neighbor_scale()
            if L["stomp"]:
                per_sec += STOMP["Mult"] * dmg * self.harvest() * 3 / (STOMP["Cooldown"] - STOMP["Step"] * (L["stomp"] - 1))
            if L["magnet"]:
                # se traga una comida pequeña cada Tick si cabe en Bites mordiscos; más radio, más a menudo
                small = foods[(zone - 1) * 3]["hp"]
                if small <= MAGNET["Bites"] * dmg * crit:
                    per_sec += small * MAGNET["Count"] / MAGNET["Tick"] * (0.6 + 0.1 * L["magnet"])
            own_rate = dmg * crit * combo / cd
            helper_bites = bites * per_sec / (own_rate + per_sec)
        bite_time = (bites - helper_bites) * cd
        hops = foods_eaten * (max(1.0, FOOD_HOP - 1.5 * L["reach"] - T["reach"]) / sp + 0.25) + max(0, foods_eaten / FOODS_PER_CLUSTER - 1) * CLUSTER_HOP / sp
        work = bite_time + hops + 1.0
        # Camino de ida y vuelta (Patas ligeras a la ida, Carga viva a la vuelta)
        # Fuera del jardín se entrega en el hormiguero de la zona: el tramo es hormiguero de zona <-> racimo
        d0 = dist(zone) if zone == 1 else depot_trip(zone)
        out = d0 / (sp * (1 + self.pv("lightSpeed") / 100))
        back = d0 / (sp * (1 + self.pv("fullSpeed") / 100))
        # (El túnel ya no acorta este tramo: sale junto a la puerta, donde está el hormiguero de zona)
        # Las alas llevan a casa o a la entrada de la zona (Abilities.wingsTarget): en el jardín acortan el
        # viaje; fuera de él no acortan el tramo hormiguero de zona <-> racimo
        if L["wings"] and zone == 1:
            cd_w = max(5, WINGS_CD - LANDING_CD * L["landing"] - T["wings"])
            flights = min(2.0, (work + out + back) / cd_w)
            legs = sorted([out, back], reverse=True)
            for i in range(2):
                take = min(1.0, max(0.0, flights - i))
                legs[i] = legs[i] * (1 - take) + min(legs[i], WINGS_FLY + 0.5) * take
            out, back = legs
        walk = out + back
        covered = 0.0
        if allies and L["bee"]:
            bspeed = BEE["Speed"] + BEE["SpeedStep"] * (L["bee"] - 1)
            btrip = 2 * max(dist(zone) / bspeed, 1.6) + 0.75  # la abeja vuela a casa (Allies), no al hormiguero de zona
            interval = max(6, max(BEE["Min"], round(BEE["Interval"] - BEE["Step"] * (L["bee"] - 1))) - T["bee"])
            wait = btrip if L["bee"] >= BEE["Full"] else max(btrip, interval)
            covered = (work + walk) / wait
        if allies and L["sling"] and dist(zone) <= SLING["Range"] + SLING["RangeStep"] * (L["sling"] - 1):
            covered += (work + walk) / (SLING["Cooldown"] - SLING["Step"] * (L["sling"] - 1))
        covered = min(covered, 0.95)
        tm = work + walk * (1 - covered)
        normal = cap / (dmg * self.harvest())
        return dict(time=tm, walk=walk * (1 - covered), work=work, bites=bites, value=value,
                    bites_per_food=bites_per_food, trip_bites=normal, presses=bites, zone=zone)

    def trip_value(self, st, tr, extras=True):
        L, T = self.L, self.T
        value = tr["value"] * st["food_mult"]
        if not extras:
            return value
        value *= self.gold_bite()
        value *= 1 + 2 * self.pv("clover") / 100
        value *= 1 + self.pv("filler") / 100
        value *= 1 + 0.1 * L["fullLoad"]
        value *= 1 + 0.1 * L["double"]
        if L["buche"]:
            value *= 1.1 + 0.05 * (L["buche"] - 1)
        mult = 1
        if self.pv("depStreak") and tr["time"] <= 20:
            mult += self.pv("depStreak") / 100 * DEP_STACKS * 0.8
        if self.pv("starDep"):
            mult *= 1 + (self.pv("starDep") - 1) * min(1, tr["time"] / 300)
        value *= mult
        value += T["deposit"] * st["food_mult"]
        return value

    def bonus(self, st, zone):
        """Comida que llega sin viaje: comida gigante, lluvia propia y lupa (Extras y Aliadas)."""
        L = self.L
        f = foods[(zone - 1) * 3 + 1]
        v = f["v"] * st["food_mult"]
        out = 0.0
        if L["giantFood"]:
            g_ = GIANT_FOOD
            out += 0.5 * (g_["Mult"] + g_["MultStep"] * (L["giantFood"] - 1) - 1) * f["hp"] * v / (g_["Interval"] - g_["Step"] * (L["giantFood"] - 1))
        if L["rain"]:
            r = RAIN
            out += (r["Count"] + r["CountStep"] * (L["rain"] - 1)) * min(r["Bites"] * st["dmg"] * self.harvest(), f["hp"]) * v / (r["Cooldown"] - r["Step"] * (L["rain"] - 1))
        if L["lens"]:
            l_ = LENS
            out += min((l_["Mult"] + l_["MultStep"] * (L["lens"] - 1)) * st["dmg"] * self.harvest(), f["hp"] * 3) * v / (l_["Interval"] - l_["Step"] * (L["lens"] - 1))
        return out

    def hand(self, st, allies=True, extras=True):
        best, bt = 0.0, None
        for z in range(1, self.depth + 1):
            tr = self.trip(st, z, allies, extras)
            if not tr:
                continue
            inc = self.trip_value(st, tr, extras) / tr["time"] + (self.bonus(st, z) if allies else 0)
            if inc > best:
                best, bt = inc, tr
        return best, bt

    # ───────────── Colonia ─────────────
    def colony(self, st, playing):
        L, T = self.L, self.T
        if self.workers <= 0:
            return 0.0
        wc = (worker_carry_at(L["workerCarry"]) + T["workerCarry"]) * SUPER ** L["super"]
        ws = (WORKER_SPEED + T["workerSpeed"]) * (1 + WORKER_SPEED_STEP * L["workerSpeed"])
        mult = BARRACKS ** L["barracks"] * LEGION ** L["legion"] * 1.5 ** self.royal.get("royalColony", 0)
        mult *= QUEEN_MULT if L["queen"] else 1
        if L["trail"] and L["smart"]:
            mult *= SMART_MULT
        if L["trail"]:
            mult *= (1 + SWEET * L["sweet"]) * (1 + T["trail"])
        if L["frenzy"]:
            mult *= 1 + (2 + L["royalPher"]) * self.frenzy_share() * playing
        best = 0.0
        caps = []  # (valor por trozo, tope) de cada zona: con varios rastros se trabajan varias zonas
        for z in range(1, self.depth + 1):
            if z > 1 and L["trail"] == 0:
                continue
            zf = [f for f in foods if f["z"] == z and not f["boss"] and (not f["hard"] or L["barracks"])]
            if not zf:
                continue
            reach = dist(z) if z == 1 else depot_trip(z)  # obreras: al hormiguero de su zona
            trip = (2 * reach / ws + WORKER_TURN) * EXPRESS ** L["express"]
            rate = (self.workers + max(0, self.pv("star") - 1)) * wc / trip * mult
            # Van a la comida que más vale; lo que no cabe en una comida (tope de su vida cada 3 s) pasa a
            # las de su racimo (Colony.luau). Tope de la zona: lo que rebrota.
            top = max(zf, key=lambda f: f["v"])
            if z == 1:
                gs = min(G_MAX, 1 + G_WSTEP * math.log10(1 + (self.workers if L["trail"] == 0 else 0) / G_WREF))
                regrow = sum(f["count"] * gs * f["hp"] * f["v"] / (BITE_TIME + f["resp"] / min(gs, G_RESP_MAX)) for f in zf) * G_DRAIN
                cap = AUTO_TARGETS * top["hp"] * top["v"] / BITE_TIME
            else:
                regrow = sum(f["count"] * f["hp"] * f["v"] / (BITE_TIME + f["resp"]) for f in zf)
                cap = L["trail"] * COLONY_SPREAD * top["hp"] * top["v"] / BITE_TIME
            value = min(rate * top["v"], cap, regrow) * self.gold_food(top)
            best = max(best, value)
            if z > 1:
                caps.append((top["v"], min(cap, regrow) * self.gold_food(top), rate))
        # Con más de un rastro, lo que no cabe en la zona más rica va a la siguiente
        if L["trail"] > 1 and caps:
            caps.sort(key=lambda c: -c[0])
            rate = caps[0][2]
            left = rate * caps[0][0]
            total = 0.0
            for v, cap_z, _ in caps[:L["trail"]]:
                take = min(left, cap_z)
                total += take
                left = (left - take) * v / caps[0][0]
                if left <= 0:
                    break
            best = max(best, total)
        col = best * st["food_mult"]
        if self.workers >= self.worker_cap() > 0:
            col *= 1 + self.pv("fullNest") / 100
        col *= 1 + self.pv("rush") / 240
        return col

    # ───────────── Todo junto ─────────────
    def income(self, playing=None):
        """Ingreso por segundo de reloj con el perfil, y su reparto."""
        f = self.active if playing is None else playing
        st = self.stats()
        base, tr = self.hand(st, allies=False, extras=False)
        with_allies, _ = self.hand(st, allies=True, extras=False)
        full, trf = self.hand(st, allies=True, extras=True)
        helpers = max(0.0, with_allies - base)
        extra_hand = max(0.0, full - with_allies)  # comida dorada, reglas de entrega, buche, etc.
        col = self.colony(st, f)
        L = self.L
        # Resto: huevos, hongos, sucesos, misiones, castas, social
        rest = 0.0
        if L["eggs"]:
            interval = max(EGG[4] * 0.6, max(EGG[4], EGG[0] - EGG[2] * L["eggs"]) - self.T["eggTime"])
            secs = EGG[1] + EGG[3] * L["eggs"] + self.T["eggValue"]
            rest += max(col * secs, EGG_FLOOR * st["dmg"] * foods[(self.depth - 1) * 3]["v"] * st["food_mult"]) / interval * f
        if L["fungus"]:
            rest += (full * f + col) * (FUNGUS[1] + FUNGUS[2] * L["fungus"] + self.T["fungus"]) / FUNGUS[0] * f
        # Sucesos del jardín: un regalo cada ~150 s mientras juegas
        zf = foods[(self.depth - 1) * 3]
        gift = max(col * GARDEN_EVENT[1], GARDEN_EVENT[2] * st["dmg"] * zf["v"] * st["food_mult"])
        rest += gift / GARDEN_EVENT[0] * f * 0.5
        # Misiones: tres huecos a la vez, cada una tarda EFFORT y paga PAY s de tu ingreso a mano
        hand_rate = full
        quests = sum(p / e for p, e in zip(QUEST_PAY, QUEST_EFFORT)) * QUEST_EFFICIENCY * max(hand_rate, col) * f
        # Castas: botín al 60 % de unas comidas pequeñas de tu zona cada 20 s
        castes = CASTE_SHARE * CASTE_FOODS * zf["hp"] * zf["v"] * st["food_mult"] / CASTE_EVERY * f if self.depth >= 2 else 0
        social = (SOCIAL_PANTRY * full + SOCIAL_OTHER * full) * f if SOCIAL_ON else 0
        hand_part = base * f
        parts = dict(mano=hand_part, colonia=col, ayudantes=helpers * f, extra=extra_hand * f, resto=rest,
                     misiones=quests, castas=castes, social=social)
        total = sum(parts.values())
        return total, parts, tr, st

    # ───────────── Opciones de compra ─────────────
    def node_cost(self, k):
        lay, mx, per, c, g = N[k]
        return K * c * STAGE ** (lay - 1) * g ** self.L[k]

    def avail(self, k):
        lay, mx, per, c, g = N[k]
        if self.depth < lay or k in SIN:
            return 0
        return min(mx, per * (self.depth - lay + 1)) if per else mx

    def options(self):
        opts = []
        L = self.L
        for k in N:
            if L[k] < self.avail(k):
                parent = PARENT.get(k)
                if parent == "workers" and self.workers == 0:
                    continue
                if parent and parent != "workers" and L.get(parent, 0) <= 0:
                    continue
                opts.append((self.node_cost(k), k))
        if L["trail"] < 3 and self.workers > 0:
            opts.append((TRAIL_COSTS[L["trail"]], "trail"))
        if self.workers < self.worker_cap():
            opts.append((WORKER_BASE * WORKER_G ** self.workers * self.cheap, "worker"))
        if self.depth < LAYERS:
            opts.append((DIG * STAGE ** (self.depth - 1), "dig"))
        for i, m in enumerate(minis):
            if m["id"] not in self.owned and m["L"] <= self.depth and (m["prev"] is None or m["prev"] in self.owned):
                opts.append((m["cost"], i))
        return opts

    def apply(self, k):
        if k == "worker":
            self.workers += 1
        elif k == "dig":
            self.depth += 1
            if self.depth == 2 and not self.royal:
                self.food += OPENING["dig"]
        elif isinstance(k, int):
            m = minis[k]
            self.owned.add(m["id"])
            if m["kind"] == "perk":
                self.PL[m["perk"]] = self.PL.get(m["perk"], 0) + 1
            elif m["kind"] == "cheap":
                self.cheap *= 1 - m["amount"]
            elif m["kind"] == "crew":
                self.T["crew"] += m["amount"]
                self.T["cup"] += 2 * m["amount"]
                if self.L["nursery"]:
                    self.workers = min(self.worker_cap(), self.workers + m["amount"])
            else:
                self.T[m["kind"]] += m["amount"]
        else:
            self.L[k] += 1

    def snapshot(self):
        return (dict(self.L), dict(self.T), dict(self.PL), self.cheap, set(self.owned), self.depth, self.workers)

    def restore(self, s):
        self.L, self.T, self.PL, self.cheap, self.owned, self.depth, self.workers = (
            dict(s[0]), dict(s[1]), dict(s[2]), s[3], set(s[4]), s[5], s[6])


def audit_key(k):
    if isinstance(k, int):
        m = minis[k]
        return f"{m['perk'] if m['kind'] == 'perk' else m['kind']}@{m['L']}"
    return k


def package(g, k):
    """Lo que de verdad se compra al elegir k: la guardería trae las obreras que caben."""
    cost = 0.0
    g.apply(k)
    if k in ("nursery", "nurse") or (isinstance(k, int) and minis[k]["kind"] == "crew"):
        while g.workers < g.worker_cap():
            cost += WORKER_BASE * WORKER_G ** g.workers * g.cheap
            g.workers += 1
    return cost


def measure(g, opts, c, k, key):
    """Ganancia del ingreso (perfil activo) al comprar k ahora y su retorno, contra lo mejor parecido."""
    snap = g.snapshot()
    base = g.income(1.0)[0]
    best = math.inf
    mine = None
    for cc, kk in opts:
        if kk == "dig" or cc < 0.25 * c:
            continue
        extra = package(g, kk)
        after = g.income(1.0)[0]
        g.restore(snap)
        roi = (cc + extra) / max(after - base, 1e-300)
        best = min(best, roi)
        if kk == k:
            mine = (after / base - 1, roi, cc + extra)
    if mine is None:
        extra = package(g, k)
        after = g.income(1.0)[0]
        g.restore(snap)
        mine = (after / base - 1, (c + extra) / max(after - base, 1e-300), c + extra)
        best = min(best, mine[1])
    return dict(key=key, label=label(k), layer=g.depth, t=g.t, gain=mine[0], roi=mine[1], best=best, cost=mine[2])


def metrics(g):
    """Las cifras de la hormiga que se pueden mirar en partida (Stats.derive): mordida, mordiscos
    normales por comida de la zona de su capa (vida / mordida), pulsaciones por comida (con la mordida
    doble y la racha de media, y Saliva ácida contra la dura), pulsaciones por viaje (carga / lo que entra
    por pulsación, Stats.tripBites) y velocidad al andar (la de las mejoras y la que se usa, con techo)."""
    st = g.stats()
    z = g.depth
    press = g.crit_avg() * g.combo_avg()
    hard_mult = (1 + VENOM_STEP * g.L["venom"]) * max(1, g.pv("crusher"))
    normal, presses = [], []
    for f in foods[(z - 1) * 3:(z - 1) * 3 + 3]:
        if f["boss"]:
            normal.append(None)
            presses.append(None)
            continue
        hm = hard_mult if f["hard"] else 1
        normal.append(math.ceil(f["hp"] / st["dmg"]))
        presses.append(math.ceil(f["hp"] / (st["dmg"] * press * hm)))
    return dict(dmg=st["dmg"], normal=normal, presses=presses, trip=st["cap"] / (st["dmg"] * g.harvest()),
                raw_speed=st["raw_speed"], speed=st["speed"], harvest=g.harvest())


def label(k):
    if isinstance(k, int):
        m = minis[k]
        return f"{m['id']} ({m['perk'] if m['kind'] == 'perk' else m['kind']})"
    return k


# ═══════════════════════════ Una partida ═══════════════════════════
def play(active, royal=None, stop_depth=LAYERS, audit=None, until_all=False):
    g = Game(active, royal)
    layers = {}
    cur = dict(start=0.0, buys=[], parts=None)
    first_buy = first_worker = None
    last_buy = 0.0
    seen = set()
    entry = {1: g.trip(g.stats(), 1)}  # viaje a la zona de la capa al empezarla (mordiscos por comida y por viaje)
    m_entry = {1: metrics(g)}
    while True:
        opts = g.options()
        if not opts:
            break
        if g.depth >= stop_depth and not until_all:
            break
        total, parts, tr, st = g.income()
        c, k = min(opts, key=lambda o: o[0])
        if audit is not None:
            key = audit_key(k)
            if key not in seen and k != "dig":
                seen.add(key)
                audit.append(measure(g, opts, c, k, key))
        if g.food < c:
            dt = (c - g.food) / total
            g.t += dt
            g.run += total * dt
            g.food = c
            # reparto acumulado de la capa
            acc = cur["parts"] or {key: 0.0 for key in parts}
            for key, v in parts.items():
                acc[key] += v * dt
            cur["parts"] = acc
        g.food -= c
        wait = g.t - last_buy
        last_buy = g.t
        if first_buy is None:
            first_buy = (g.t, label(k))
        if not g.prized:
            g.prized = True
            g.food += sum(OPENING["prizes"])
        if k == "worker" and first_worker is None:
            first_worker = g.t
        cur["buys"].append((g.t, wait, k))
        cur.setdefault("trips", []).append((g.t, g.trip(g.stats(), g.depth)))
        cur.setdefault("metrics", []).append((g.t, metrics(g)))
        if k == "dig":
            st = g.stats()
            _, _, tr_before, _ = g.income()
            layers[g.depth] = dict(start=cur["start"], end=g.t, buys=cur["buys"], parts=cur["parts"] or {},
                                   trip=tr_before, stats=st, trips=cur.get("trips", []), metrics=cur.get("metrics", []))
            cur = dict(start=g.t, buys=[], parts=None)
        g.apply(k)
        if k == "dig":
            _, _, tr_new, st_new = g.income()
            entry[g.depth] = g.trip(st_new, g.depth)
            m_entry[g.depth] = metrics(g)
        if g.t > 3600 * 500:
            break
    # Última capa: hasta tenerlo todo comprado
    if until_all and cur["buys"]:
        _, _, tr_last, st_last = g.income()
        layers[g.depth] = dict(start=cur["start"], end=g.t, buys=cur["buys"], parts=cur["parts"] or {},
                               trip=tr_last, stats=st_last, next_trip=None, trips=cur.get("trips", []),
                               metrics=cur.get("metrics", []))
    for d in layers:
        layers[d]["entry"] = entry.get(d)
        layers[d]["m_entry"] = m_entry.get(d)
    return g, layers, first_buy, first_worker


# ═══════════════════════════ Informe ═══════════════════════════
def layer_rows(layers):
    rows = []
    for d in sorted(layers):
        info = layers[d]
        dur = info["end"] - info["start"]
        buys = info["buys"]
        longest = max((w for _, w, _ in buys), default=0)
        early = sum(1 for tt, _, _ in buys if tt - info["start"] <= 0.2 * dur)
        parts = info["parts"]
        tot = sum(parts.values()) or 1
        trip = info.get("entry") or info["trip"]
        # Mordiscos por comida a media capa (con lo comprado hasta entonces), en la zona de la capa
        mid = info["start"] + dur / 2
        trips = info.get("trips") or [(info["start"], trip)]
        mid_trip = min(trips, key=lambda x: abs(x[0] - mid))[1] or trip
        bpf = mid_trip["bites_per_food"] if mid_trip else {}
        ms_list = info.get("metrics") or []
        m_mid = min(ms_list, key=lambda x: abs(x[0] - mid))[1] if ms_list else info.get("m_entry")
        m_all = [x[1] for x in ms_list]
        rows.append(dict(layer=d, start=info["start"], dur=dur, n=len(buys), longest=longest,
                         early=early / max(1, len(buys)), parts={k: v / tot for k, v in parts.items()},
                         bpf=bpf, trip_bites=trip["trip_bites"] if trip else 0,
                         trip_time=trip["time"] if trip else 0, walk=trip["walk"] if trip else 0,
                         zone=trip["zone"] if trip else 0, entry_trip=trip["trip_bites"] if trip else None,
                         m_entry=info.get("m_entry"), m_mid=m_mid,
                         max_trip=max([m["trip"] for m in m_all] or [0]),
                         max_speed=max([m["speed"] for m in m_all] or [0])))
    return rows


def print_profile(name, rows, first_buy, first_worker):
    print(f"\n== {name} ==  primera compra {first_buy[0]:.0f} s ({first_buy[1]}), primera obrera "
          f"{(first_worker or 0) / 60:.1f} min")
    print("capa  min.total  +min  compras  espera.max  1er20%  mano col ayud extra rest misi cast soc   "
          "mordiscos/comida(p,m,g)  /viaje  viaje(s) andar(s)")
    for r in rows:
        p = r["parts"]
        bpf = r["bpf"]
        print(f"{r['layer']:4d} {(r['start'] + r['dur']) / 60:9.1f} {r['dur'] / 60:6.1f} {r['n']:7d} "
              f"{r['longest'] / 60:8.1f}m  {100 * r['early']:5.0f}%  "
              + " ".join(f"{100 * p.get(k, 0):3.0f}" for k in
                         ("mano", "colonia", "ayudantes", "extra", "resto", "misiones", "castas", "social"))
              + f"   {bpf.get(0, '-'):>4} {bpf.get(1, '-'):>4} {bpf.get(2, '-'):>4}"
              + f"   {r['trip_bites']:6.1f}  {r['trip_time']:7.1f}  {r['walk']:6.1f}")


def print_metrics(rows):
    print("   Cifras de la hormiga (zona de su capa). inicio = al excavarla con lo de antes comprado; media = a mitad de capa")
    print("   capa | inicio: mordida  normales p/m/g    pulsaciones p/m/g  puls/viaje  vel(mejoras->usada) | media: mordida  normales p/m/g    pulsaciones p/m/g  puls/viaje  vel")

    def fmt(m):
        if not m:
            return " " * 60
        n = "/".join("-" if x is None else str(x) for x in m["normal"])
        q = "/".join("-" if x is None else str(x) for x in m["presses"])
        return f"{m['dmg']:9.3g}  {n:>15s}  {q:>15s}  {m['trip']:9.1f}  {m['raw_speed']:5.0f}->{m['speed']:3.0f}"
    for r in rows:
        print(f"   {r['layer']:4d} | {fmt(r['m_entry'])} | {fmt(r['m_mid'])}")


CHECKS = []


def check(ok, text):
    CHECKS.append((ok, text))


def verify(active_rows, casual_rows, fb_a, fw_a, reb):
    a = {r["layer"]: r for r in active_rows}
    c = {r["layer"]: r for r in casual_rows}
    check(fb_a[0] <= 40, f"primera compra en ~30 s (activo): {fb_a[0]:.0f} s")
    check(fw_a is not None and 120 <= fw_a <= 260, f"primera obrera ~3 min (activo): {(fw_a or 0) / 60:.1f} min")
    t2a, t2c = a[1]["dur"] / 60, c[1]["dur"] / 60
    check(8 <= t2a <= 11.5, f"capa 2 a los 8-11 min (activo): {t2a:.1f} min")
    check(t2c <= 20, f"capa 2 en menos de 20 min (casual): {t2c:.1f} min")
    durs = []
    for L in sorted(a):
        if L == 1 or L == LAYERS:
            continue
        da, dc = a[L]["dur"] / 60, c[L]["dur"] / 60
        durs.append(da)
        check(20 <= da <= 45, f"capa {L}->{L + 1}: 20-45 min activo ({da:.1f})")
        check(dc <= 2.2 * da + 0.01, f"capa {L}->{L + 1}: casual <= x2.2 del activo ({dc / max(da, 1e-9):.2f})")
    for i in range(1, len(durs)):
        ratio = max(durs[i], durs[i - 1]) / max(1e-9, min(durs[i], durs[i - 1]))
        check(ratio <= 1.6, f"capas vecinas {i + 1}/{i + 2} dentro de x1.6 ({ratio:.2f})")
    for L in sorted(a):
        if L == LAYERS:
            continue
        check(a[L]["longest"] <= 240, f"capa {L}: espera más larga entre compras < 4 min activo ({a[L]['longest'] / 60:.1f})")
        check(c[L]["longest"] <= 480, f"capa {L}: espera más larga < 8 min casual ({c[L]['longest'] / 60:.1f})")
        check(a[L]["early"] <= 0.7, f"capa {L}: <= 70 % de compras en el primer 20 % ({100 * a[L]['early']:.0f} %)")
    half = LAYERS // 2
    for L in sorted(a):
        p = a[L]["parts"]
        if L <= half:
            hand = p.get("mano", 0) + p.get("extra", 0)
            others = {k: v for k, v in p.items() if k not in ("mano", "extra")}
            check(hand >= max(others.values()), f"capa {L}: la mano es el ingreso principal ({100 * hand:.0f} %)")
        if L >= 2:
            check(0.15 <= p.get("colonia", 0) <= 0.40, f"capa {L}: colonia 15-40 % ({100 * p.get('colonia', 0):.0f} %)")
        check(p.get("social", 0) <= 0.10 + 1e-9, f"capa {L}: social <= 10 % ({100 * p.get('social', 0):.0f} %)")
        handish = p.get("mano", 0) + p.get("extra", 0) + p.get("ayudantes", 0)
        q = p.get("misiones", 0) / max(handish, 1e-9)
        check(0.20 <= q <= 0.45, f"capa {L}: misiones, extra de ~25-35 % sobre lo ganado a mano ({100 * q:.0f} %)")
        for k in ("ayudantes", "misiones", "castas", "resto"):
            check(p.get(k, 0) <= 0.30, f"capa {L}: {k} no trivializa (<= 30 %, {100 * p.get(k, 0):.0f} %)")
    names = ("pequeña", "mediana", "grande")
    mid_ok = ((2.5, 6), (7, 16), (20, 45))   # 3-5 / 8-14 / 25-40 con un poco de holgura
    entry_max = (10, 28, 80)                 # al entrar, como mucho ~el doble
    for L in sorted(a):
        r = a[L]
        me, mm = r["m_entry"], r["m_mid"]
        for i in range(3):
            if me and me["presses"][i] is not None:
                check(me["presses"][i] <= entry_max[i], f"capa {L}: {names[i]} al empezar <= {entry_max[i]} pulsaciones ({me['presses'][i]})")
            if mm and mm["presses"][i] is not None and L < LAYERS:
                lo, hi = mid_ok[i]
                check(lo <= mm["presses"][i] <= hi, f"capa {L}: {names[i]} a media capa {lo:g}-{hi:g} pulsaciones ({mm['presses'][i]})")
        if me:
            check(12 <= me["trip"] <= 25.5, f"capa {L}: viaje de 12-25 pulsaciones al empezar ({me['trip']:.1f})")
        check(r["max_trip"] <= 40, f"capa {L}: viaje de 40 pulsaciones como mucho ({r['max_trip']:.1f})")
        check(r["max_speed"] <= MAX_WALK + 0.01, f"capa {L}: velocidad al andar <= {MAX_WALK:g} ({r['max_speed']:.0f})")
    if reb:
        for R, gain, jelly in reb:
            check(jelly >= 1, f"enjambre en capa {R}: da jalea ({jelly})")
        best = [x for x in reb if 7 <= x[0] <= 9]
        ok = any(0.40 <= g_ <= 0.60 for _, g_, _ in best)
        check(ok, "primer enjambre en capas 7-9 y segunda vuelta 40-60 % más rápida: "
              + ", ".join(f"capa {R}: {100 * g_:.0f} %" for R, g_, _ in best))


def rebirth_check(active):
    out = []
    for R in (7, 8, 9):
        g1, lay1, _, _ = play(active, stop_depth=R)
        t1 = g1.t
        jelly = jelly_for(g1.run)
        # Gasta la jalea en el árbol real: siempre lo más barato
        royal = {k: 0 for k in ROYAL}
        j = jelly
        while True:
            opts = [(ROYAL[k][1] + ROYAL[k][2] * royal[k], k) for k in ROYAL if royal[k] < ROYAL[k][0]]
            opts = [o for o in opts if o[0] <= j]
            if not opts:
                break
            c, k = min(opts)
            j -= c
            royal[k] += 1
        g2, _, _, _ = play(active, royal=royal, stop_depth=R)
        out.append((R, 1 - g2.t / max(t1, 1e-9), jelly))
    return out


def calibrate():
    """Mide al empezar cada capa lo que pega de más una pulsación (galerías, mordida doble, racha) y contra
    la comida dura: es Config.FoodCurve.Press / HardPress."""
    g = Game(0.85)
    press, hard = [1.0], [1.0]
    while g.depth < LAYERS:
        opts = g.options()
        c, k = min(opts, key=lambda o: o[0])
        total = g.income()[0]
        if g.food < c:
            g.t += (c - g.food) / total
            g.food = c
        g.food -= c
        g.apply(k)
        if k == "dig":
            st = g.stats()
            press.append(st["dmg"] / st["lvl_dmg"] * g.crit_avg() * g.combo_avg())
            hard.append((1 + VENOM_STEP * g.L["venom"]) * max(1, g.pv("crusher")))
    print("PRESS=" + ",".join(f"{x:.2g}" for x in press))
    print("HARD_PRESS=" + ",".join(f"{x:.2g}" for x in hard))


def main():
    if "--calibrar" in ARGS:
        calibrate()
        return
    profiles = [("activo (85 %)", 0.85), ("casual (45 %)", 0.45), ("ausente (10 %)", 0.10)]
    if "--perfil" in ARGS:
        v = float(ARGS[ARGS.index("--perfil") + 1])
        profiles = [(f"a medida ({100 * v:.0f} %)", v)]
    results = {}
    audit = [] if AUDIT else None
    for name, f in profiles:
        g, layers, fb, fw = play(f, audit=audit if f == 0.85 else None, until_all=True)
        rows = layer_rows(layers)
        results[f] = (rows, fb, fw, g)
        print_profile(name, rows, fb, fw)
        if f == 0.85 or len(profiles) == 1:
            print_metrics(rows)
        print(f"   todo comprado: {g.t / 3600:.1f} h; obreras {g.workers}; galerías {len(g.owned)}")
    print("\nComida por zona (vida, valor, mordiscos de referencia a media capa):")
    for z in range(1, LAYERS + 1):
        fs = [f for f in foods if f["z"] == z]
        print(f"  zona {z:2d}: " + "  ".join(f"{f['id']} {f['hp']:.3g}/{f['v']:.3g}" for f in fs)
              + f"   ref. mordida {ref_damage(z):.3g}   distancia {dist(z):.0f}")
    print(f"Por zona (2+): {PER_ZONE[0]} pequeñas, {PER_ZONE[1]} medianas, {PER_ZONE[2]} grandes + "
          f"{PER_ZONE[3]} jefa = {sum(PER_ZONE)} comidas; con el jardín (x2,4 como mucho) "
          f"{13 * sum(PER_ZONE) + 1 + int(sum(GARDEN_COUNTS) * G_MAX)} modelos")
    if 0.85 in results and 0.45 in results:
        reb = rebirth_check(0.85)
        print("\nEnjambre: " + "; ".join(f"en capa {R}: {jelly} jalea, segunda vuelta {100 * gain:.0f} % más rápida"
                                         for R, gain, jelly in reb))
        ra, fba, fwa, _ = results[0.85]
        rc, _, _, _ = results[0.45]
        verify(ra, rc, fba, fwa, reb)
        fails = [t for ok, t in CHECKS if not ok]
        print(f"\nVerificación: {len(CHECKS) - len(fails)} APROBADO, {len(fails)} FALLA")
        for ok, t in CHECKS:
            if VERBOSE or not ok:
                print(("  APROBADO  " if ok else "  FALLA     ") + t)
    if audit is not None:
        print_audit(audit)
        royal_audit()


def royal_audit():
    """Árbol real: cuánto acorta un nivel (el primero) de cada mejora la segunda vuelta hasta la capa 7."""
    print("\nÁrbol real (jalea): un nivel de cada cosa, cuánto acorta la vuelta hasta la capa 7 (perfil activo)")
    base, _, _, _ = play(0.85, royal={"royalFood": 0}, stop_depth=7)
    for k, (mx, c, step) in ROYAL.items():
        g, _, _, _ = play(0.85, royal={k: 1}, stop_depth=7)
        gain = 1 - g.t / base.t
        verdict = "ok" if gain >= 0.03 else "flojo"
        print(f"  {k:12s} cuesta {c:2d} de jalea   la vuelta dura {g.t / 60:6.1f} min ({100 * gain:5.1f} % menos)   {verdict}")


def print_audit(audit):
    print("\nAuditoría (perfil activo): ganancia del ingreso al comprar un nivel la primera vez que se puede, "
          "y retorno = costo / ganancia por segundo")
    print(f"{'mejora':22s} capa    min    ganancia   retorno   mejor ret.  veredicto")
    useless = 0
    by_kind = {}
    for a in audit:
        ratio = a["roi"] / max(a["best"], 1e-30)
        offline = a["key"] in OFFLINE or a["key"] in QOL
        bad = a["gain"] < 0.03 and not offline
        verdict = (QOL.get(a["key"]) or "fuera de línea") if offline else ("inútil" if bad else ("flojo" if ratio > 3 else "ok"))
        if "@" in a["key"]:
            kind = a["key"].split("@")[0]
            by_kind.setdefault(kind, []).append((a, ratio, bad))
            continue
        useless += bad
        roi = f"{a['roi']:8.0f} s" if a["roi"] < 1e12 else "       - "
        tag = f" (x{ratio:.1f})" if ratio > 3 and ratio < 1e6 else ""
        print(f"{a['label']:22s} {a['layer']:4d} {a['t'] / 60:6.1f}  {100 * a['gain']:8.2f} %  {roi} "
              f"{a['best']:8.0f} s   {verdict}{tag}")
    print("\nGalerías, por tipo (mediana de la ganancia, peor retorno relativo, cuántas fallan):")
    for kind, items in sorted(by_kind.items()):
        gains = sorted(x[0]["gain"] for x in items)
        worst = max(x[1] for x in items)
        nbad = sum(1 for x in items if x[2])
        worst_txt = f"x{worst:5.1f}" if worst < 1e6 else "  -   "
        nbad = sum(1 for x in items if x[0]["gain"] < 0.01)
        print(f"  {kind:12s} {len(items):3d} galerías  ganancia mediana {100 * gains[len(gains) // 2]:6.2f} %  "
              f"peor retorno {worst_txt}  por debajo del 1 %: {nbad}")
    print(f"Nodos del árbol que fallan: {useless}")


if __name__ == "__main__":
    main()
