-- Anima a todas las hormigas de jugadores: patas en trípode con rodillas que se doblan, cuerpo que
-- bota y se inclina al correr, abdomen que se menea, antenas acodadas que ondean, se animan al ver
-- comida y caen con la carga llena. La tuya además da un tirón de cabeza y cierra las pinzas al
-- morder (AntAnim.bite) y da un saltito al comprar (AntAnim.cheer). Se hace en cada cliente para no
-- gastar red.
--
-- Nada se acumula: cada fotograma el C0 de cada unión se calcula desde su pose de reposo
-- (atributo "Base" en los Motor6D; C0 del servidor guardado aparte en las Weld).
--
-- Nada puede separarse: el cuerpo entero se mueve como un bloque (una sola transformación en el
-- espacio de la raíz que reciben a la vez tórax, cabeza, abdomen y caderas) y la cabeza y el
-- abdomen solo GIRAN un poco sobre su unión, cuyo punto está dentro de las dos piezas que une.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AntModel = require(ReplicatedStorage.Shared.AntModel)
local Targeting = require(script.Parent.Targeting)

local AntAnim = {}

local TAU = math.pi * 2
local SWING = math.rad(26) -- giro de cadera adelante/atrás
local STEP_LIFT = 0.34 -- radianes que se levanta la pata al avanzar
local KNEE_FOLD = 0.5 -- radianes que se dobla la rodilla al levantar la pata
local PLANT_MAX = 0.3 -- corrección máxima para mantener el pie en el suelo
local BITE_TIME = 0.18
local CHEER_TIME = 0.7
local PERK_TIME = 0.7
-- Trípode: delantera izq, media der y trasera izq van juntas; las otras tres en contrafase
local TRIPOD = { 0, math.pi, math.pi, 0, 0, math.pi }

local LEAN = 0.05 -- radianes de inclinación por cada rad/s de giro
local LEAN_MAX = 0.14

local localPlayer = Players.LocalPlayer
-- Reloj propio del mordisco: se para durante la parada de impacto (AntAnim.hitStop)
local animClock = 0
local freezeUntil = 0
local biteAt = -math.huge
local cheerAt = -math.huge
local perkAt = -math.huge
local lastTarget: Model? = nil

local baseC0: { [Motor6D]: CFrame } = {}

type AntState = {
	phase: number,
	speed: number,
	heavy: number,
	sprint: number,
	lookVersion: any,
	yaw: number?, -- rumbo del fotograma anterior (para la inclinación en los giros)
	lean: number,
	-- Emote que manda en esta hormiga (AntAnim.override) y cuándo empezó
	emote: ((number, number, any) -> boolean?)?,
	emoteAt: number?,
}
-- Tablas normales, no débiles: una tabla débil con instancias como clave pierde entradas en cada
-- recolección de basura aunque la instancia siga viva. Se limpian al destruirse la instancia.
local states: { [Model]: AntState } = {}

-- Pose de reposo de cada Weld animada: `rest` es el C0 que puso el servidor y `written` lo último
-- que escribimos. Si el C0 actual no es lo que escribimos, lo cambió el servidor: es la nueva pose.
type WeldPose = { rest: CFrame, written: CFrame }
local weldPoses: { [Weld]: WeldPose } = {}

local function base(motor: Motor6D): CFrame
	-- El servidor publica la pose de reposo en el atributo "Base" (AntModel / AntLook) y la
	-- actualiza al reescalar o cambiar el aspecto; sin atributo se usa el C0 visto la primera vez.
	local published = motor:GetAttribute("Base")
	if typeof(published) == "CFrame" then
		return published
	end
	local c0 = baseC0[motor]
	if not c0 then
		c0 = motor.C0
		baseC0[motor] = c0
		motor.Destroying:Once(function()
			baseC0[motor] = nil
		end)
	end
	return c0
end

local function weldRest(weld: Weld): CFrame
	local current = weld.C0
	local pose = weldPoses[weld]
	if not pose then
		pose = { rest = current, written = current }
		weldPoses[weld] = pose
		weld.Destroying:Once(function()
			weldPoses[weld] = nil
		end)
	elseif current ~= pose.written then
		pose.rest = current
		pose.written = current
	end
	return pose.rest
end

local function writeWeld(weld: Weld, c0: CFrame)
	local pose = weldPoses[weld]
	if pose and pose.written == c0 then
		return
	end
	weld.C0 = c0
	if pose then
		-- Se guarda lo que devuelve la propiedad, para comparar con exactitud el fotograma siguiente
		pose.written = weld.C0
	end
end

-- Al cambiar el aspecto se vuelven a leer las Weld que estaban en reposo; las que estaban a mitad de
-- animación se corrigen solas porque su C0 ya no coincide con lo último que escribimos.
local function forgetIdleWelds(parent: Instance?)
	if not parent then
		return
	end
	for _, child in parent:GetChildren() do
		if child:IsA("Weld") then
			local pose = weldPoses[child]
			if pose and pose.written == pose.rest then
				weldPoses[child] = nil
			end
		end
	end
end

local function stateOf(character: Model): AntState
	local st = states[character]
	if not st then
		st = { phase = 0, speed = 0, heavy = 0, sprint = 0, lookVersion = character:GetAttribute("LookVersion"), yaw = nil, lean = 0 }
		states[character] = st
		character.Destroying:Once(function()
			states[character] = nil
		end)
	end
	return st
end

local function easeOut(x: number): number
	return 1 - (1 - x) * (1 - x)
end

local function smooth(x: number): number
	return x * x * (3 - 2 * x)
end

-- Tirón de mordisco: sale rápido (30 %) y vuelve suave. 0..1
local function lungeCurve(u: number): number
	if u < 0 or u >= 1 then
		return 0
	elseif u < 0.3 then
		return easeOut(u / 0.3)
	end
	return 1 - smooth((u - 0.3) / 0.7)
end

-- Mandíbulas: se abren, se cierran de golpe pasándose un poco y vuelven. Radianes.
local function jawCurve(u: number): number
	if u < 0 or u >= 1 then
		return 0
	elseif u < 0.35 then
		return math.sin(u / 0.35 * math.pi / 2) * 0.55
	elseif u < 0.55 then
		local k = (u - 0.35) / 0.2
		return 0.55 + (-0.14 - 0.55) * k * k
	end
	return -0.14 * (1 - smooth((u - 0.55) / 0.45))
end

-- Saltito de celebración en studs (antes de escalar): agacharse, saltar, aterrizar
local function hopCurve(u: number): number
	if u < 0 or u >= 1 then
		return 0
	elseif u < 0.12 then
		return -0.18 * math.sin(u / 0.12 * math.pi)
	elseif u < 0.6 then
		return 0.95 * math.sin((u - 0.12) / 0.48 * math.pi)
	elseif u < 0.72 then
		return -0.12 * math.sin((u - 0.6) / 0.12 * math.pi)
	end
	return 0
end

-- Cadera + rodilla de una pata. `step` 0..1 es cuánto está en el aire (fase de avance).
local function animateLeg(joint: Motor6D, leg: number, body: CFrame, plant: CFrame?, yaw: number, step: number, scale: number)
	local c0 = base(joint)
	local out = Vector3.new(c0.XVector.X, 0, c0.XVector.Z)
	out = if out.Magnitude > 1e-3 then out.Unit else Vector3.xAxis
	local raise = step * STEP_LIFT
	-- Compensa el bote, el hundimiento y la inclinación del cuerpo para que el pie siga en el suelo:
	-- levantar la pata un ángulo a sube el pie ≈ a × su distancia horizontal a la cadera
	local foot = joint:GetAttribute("Foot")
	if plant and typeof(foot) == "Vector3" then
		local reach = (foot - c0.Position / scale):Dot(out)
		if reach > 0.3 then
			local moved = (plant * (foot * scale)).Y / scale - foot.Y
			raise -= math.clamp(moved / reach, -PLANT_MAX, PLANT_MAX)
		end
	end
	local pose = CFrame.new(c0.Position)
	if yaw ~= 0 then
		pose *= CFrame.Angles(0, yaw, 0)
	end
	if raise ~= 0 then
		pose *= CFrame.fromAxisAngle(out:Cross(Vector3.yAxis), raise)
	end
	joint.C0 = body * pose * c0.Rotation

	local upper = joint.Part1
	local knee = upper and upper:FindFirstChild("Knee" .. leg)
	if knee and knee:IsA("Motor6D") then
		local k0 = base(knee)
		local fold = step * KNEE_FOLD
		-- Su eje Z es la bisagra de la rodilla: girar en + la dobla más (el pie se recoge)
		knee.C0 = if fold == 0 then k0 else k0 * CFrame.Angles(0, 0, fold)
	end
end

-- Pose de emote: desplazamientos sobre la pose de reposo que rellena la función del emote cada
-- fotograma. `body` va en el espacio de la raíz a escala 1 (aquí se escala) y mueve el cuerpo entero
-- como un bloque; head/abdomen giran sobre su unión; legs[i] gira la cadera i en el espacio de la
-- raíz y knees[i] dobla la rodilla (radianes, + dobla); antennae[1|2] gira cada antena en el espacio
-- de la cabeza y elbows[1|2] dobla su codo; jaw abre las pinzas (radianes). Lo que no se rellena
-- queda en reposo. Una sola tabla reutilizada: se vacía antes de cada llamada.
local emotePose = {
	body = CFrame.identity,
	head = CFrame.identity,
	abdomen = CFrame.identity,
	legs = {} :: { [number]: CFrame },
	knees = {} :: { [number]: number },
	antennae = {} :: { [number]: CFrame },
	elbows = {} :: { [number]: number },
	jaw = 0,
	scale = 1,
}

-- Llama a la función del emote y escribe su pose. Devuelve false si el emote terminó (o falló):
-- entonces la animación normal escribe ese mismo fotograma todas las uniones desde su reposo.
local function runEmote(st: AntState, root: BasePart, head: Instance?, scale: number, dt: number, now: number): boolean
	local fn: any = st.emote
	local p = emotePose
	p.body, p.head, p.abdomen, p.jaw, p.scale = CFrame.identity, CFrame.identity, CFrame.identity, 0, scale
	table.clear(p.legs)
	table.clear(p.knees)
	table.clear(p.antennae)
	table.clear(p.elbows)
	local ok, keep = pcall(fn, dt, now - (st.emoteAt or now), p)
	if not ok or keep == false then
		if not ok then
			warn("[CRUNCH!] Emote:", keep)
		end
		if st.emote == fn then
			st.emote = nil
		end
		return false
	end

	local body = p.body
	body = CFrame.new(body.Position * scale) * body.Rotation
	for _, joint in root:GetChildren() do
		if joint:IsA("Motor6D") then
			local leg = tonumber(joint.Name:match("^Leg(%d)$"))
			if leg then
				local c0 = base(joint)
				joint.C0 = body * CFrame.new(c0.Position) * (p.legs[leg] or CFrame.identity) * c0.Rotation
				local upper = joint.Part1
				local knee = upper and upper:FindFirstChild("Knee" .. leg)
				if knee and knee:IsA("Motor6D") then
					knee.C0 = base(knee) * CFrame.Angles(0, 0, p.knees[leg] or 0)
				end
			elseif joint.Name == "HeadJoint" then
				joint.C0 = body * base(joint) * p.head
			elseif joint.Name == "AbdomenJoint" then
				joint.C0 = body * base(joint) * p.abdomen
			end
		elseif joint:IsA("Weld") then
			local part1 = joint.Part1
			if part1 and part1.Name == "Thorax" then
				writeWeld(joint, body * weldRest(joint))
			end
		end
	end
	if head then
		for _, joint in head:GetChildren() do
			if joint:IsA("Motor6D") and (joint.Name == "Antenna1" or joint.Name == "Antenna2") then
				local i = if joint.Name == "Antenna1" then 1 else 2
				local c0 = base(joint)
				joint.C0 = CFrame.new(c0.Position) * (p.antennae[i] or CFrame.identity) * c0.Rotation
				local scape = joint.Part1
				local elbow = scape and scape:FindFirstChild("AntennaElbow" .. i)
				if elbow and elbow:IsA("Motor6D") then
					elbow.C0 = base(elbow) * CFrame.Angles(0, 0, p.elbows[i] or 0)
				end
			elseif joint:IsA("Weld") then
				local part1 = joint.Part1
				if part1 and part1.Name == "Mandible" and part1:IsA("BasePart") then
					local rest = weldRest(joint)
					if p.jaw == 0 then
						writeWeld(joint, rest)
					else
						local s = if rest.X < 0 then -1 else 1
						local hinge = (part1.Size.Z - AntModel.JawOverlap * scale) / 2
						writeWeld(joint, rest * CFrame.new(0, 0, hinge) * CFrame.Angles(0, -s * p.jaw, 0) * CFrame.new(0, 0, -hinge))
					end
				end
			end
		end
	end
	return true
end

local function animate(player: Player, character: Model, now: number, dt: number)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local head = character:FindFirstChild("Head")
	local st = stateOf(character)
	local isLocal = player == localPlayer

	local version = character:GetAttribute("LookVersion")
	if version ~= st.lookVersion then
		st.lookVersion = version
		st.emote = nil -- reconstruida a mitad de un emote: se corta y vuelve la animación normal
		forgetIdleWelds(root)
		forgetIdleWelds(head)
	end

	-- Un emote (client/Emotes) tiene el control: este fotograma no se anima nada más
	if st.emote and runEmote(st, root, head, character:GetScale(), dt, now) then
		return
	end

	local scale = character:GetScale()
	local rawSpeed = (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
	local blend = math.min(1, dt * 10)
	st.speed += (rawSpeed - st.speed) * blend

	local walk = math.max(tonumber(player:GetAttribute("WalkSpeed")) or 10, 1)
	local capacity = tonumber(player:GetAttribute("Capacity")) or 0
	local carry = tonumber(player:GetAttribute("Carry")) or 0
	local full = capacity > 0 and carry >= capacity
	st.heavy += ((if full then 1 else 0) - st.heavy) * math.min(1, dt * 4)
	st.sprint += (math.clamp((st.speed / walk - 1.3) / 0.5, 0, 1) - st.sprint) * math.min(1, dt * 6)
	-- Los suavizados nunca llegan a cero solos: se redondean para que en reposo la pose sea exacta
	if st.speed < 0.05 then
		st.speed = 0
	end
	if st.heavy < 0.002 then
		st.heavy = 0
	end
	if st.sprint < 0.002 then
		st.sprint = 0
	end

	-- Inclinación en los giros: el cuerpo se tumba hacia dentro de la curva según lo rápido que gira
	-- y lo rápido que corre. Entra en el balanceo (roll) del cuerpo, que los pies ya compensan.
	local look = root.CFrame.LookVector
	local yawNow = math.atan2(-look.X, -look.Z)
	local turnRate = 0
	if st.yaw and dt > 0 then
		turnRate = ((yawNow - st.yaw + math.pi) % TAU - math.pi) / dt
	end
	st.yaw = yawNow
	local leanGoal = if st.speed > 0.5 then math.clamp(turnRate * LEAN * math.min(st.speed / walk, 1.2), -LEAN_MAX, LEAN_MAX) else 0
	st.lean += (leanGoal - st.lean) * math.min(1, dt * 8)
	if leanGoal == 0 and math.abs(st.lean) < 0.002 then
		st.lean = 0
	end

	local heavy, sprint = st.heavy, st.sprint
	local move = math.clamp(st.speed / walk, 0, 1.2)
	local moving = st.speed > 0.5
	local frozen = isLocal and now < freezeUntil
	-- Fase integrada: cambiar de velocidad no da tirones. Con carga llena el paso es más lento.
	-- Durante la parada de impacto tu hormiga se queda congelada un instante.
	if not frozen then
		st.phase = (st.phase + dt * (7 + st.speed * 0.8) * (1 - 0.3 * heavy)) % TAU
	end
	local beat = st.phase

	local biteK = if isLocal then lungeCurve((animClock - biteAt) / BITE_TIME) else 0
	local jaw = if isLocal then jawCurve((animClock - biteAt) / BITE_TIME) else 0
	local cheerU = if isLocal then (now - cheerAt) / CHEER_TIME else 1
	local hop = hopCurve(cheerU)

	-- Pose del cuerpo entero (en el espacio de la raíz): bote, hundirse con carga, inclinarse al
	-- correr y un tirón hacia delante al morder. Las inclinaciones giran sobre el centro del tórax.
	local bob = if moving then (math.abs(math.sin(beat)) - 0.5) * 2 * (0.09 - 0.035 * heavy) * move else 0
	local sink = -0.12 * heavy
	local lunge = 0.16 * biteK
	local pitch = -(0.05 * move + 0.11 * sprint + 0.04 * heavy * move) - 0.05 * biteK
	local roll = (if moving then math.sin(beat) * 0.035 * move else 0) + st.lean
	local planted = bob == 0 and sink == 0 and lunge == 0 and pitch == 0 and roll == 0
	local plant: CFrame? = nil -- parte de la pose que los pies deben compensar (todo menos el salto)
	if not planted then
		local pivot = CFrame.new(0, 0.1 * scale, -0.3 * scale)
		plant = CFrame.new(0, (bob + sink) * scale, -lunge * scale) * pivot * CFrame.Angles(pitch, 0, roll) * pivot:Inverse()
	end
	local still = planted and hop == 0
	local body = if still then CFrame.identity else CFrame.new(0, hop * scale, 0) * (plant or CFrame.identity)

	local swingAmp = SWING * (0.6 + 0.4 * math.min(move, 1)) * (1 + 0.25 * sprint)
	local stepAmp = math.min(move, 1) * (1 - 0.4 * heavy)

	for _, joint in root:GetChildren() do
		if joint:IsA("Motor6D") then
			local leg = tonumber(joint.Name:match("^Leg(%d)$"))
			if leg then
				local c0 = base(joint)
				local s = if c0.X < 0 then -1 else 1
				local t = beat + (TRIPOD[leg] or 0)
				-- El pie avanza con sin(t) y va en el aire mientras avanza (cos(t) > 0)
				local yaw = if moving then s * math.sin(t) * swingAmp else 0
				local step = if moving then math.max(0, math.cos(t)) * stepAmp else 0
				animateLeg(joint, leg, body, plant, yaw, step, scale)
			elseif joint.Name == "HeadJoint" then
				local c0 = base(joint)
				-- Solo giros sobre el cuello (que está dentro de la cabeza y del cuello del tórax)
				local nod = (if moving then math.sin(beat * 2) * 0.05 + math.sin(beat) * 0.04 else math.sin(now * 2) * 0.025)
					- 0.08 * heavy
					+ 0.22 * math.max(hop, 0)
					- 0.32 * biteK
				local turn = if moving then 0 else math.sin(now * 0.8) * 0.06
				local tilt = if moving then math.sin(beat) * 0.04 * move else 0
				joint.C0 = body * c0 * CFrame.Angles(math.clamp(nod, -0.42, 0.3), turn, tilt)
			elseif joint.Name == "AbdomenJoint" then
				local c0 = base(joint)
				local wag = if moving then math.sin(beat) * 0.12 * math.max(move, 0.4) else math.sin(now * 1.5) * 0.035
				local sway = if moving then math.sin(beat + 0.6) * 0.05 * move else 0
				-- Con carga llena el abdomen cuelga; al morder se echa un poco atrás para compensar
				local droop = 0.12 * heavy + 0.08 * biteK
				-- Giros pequeños sobre el pecíolo: el punto de giro está dentro del abdomen y del pecíolo
				joint.C0 = body * c0 * CFrame.Angles(math.clamp(droop, 0, 0.2), math.clamp(wag, -0.14, 0.14), math.clamp(sway, -0.06, 0.06))
			end
		elseif joint:IsA("Weld") then
			local part1 = joint.Part1
			if part1 and part1.Name == "Thorax" then
				local rest = weldRest(joint)
				writeWeld(joint, if still then rest else body * rest)
			end
		end
	end

	if not head then
		return
	end

	-- Antenas: arriba al aparecer comida, caídas y abiertas con la carga llena, molinillo al celebrar
	local perkU = (now - perkAt) / PERK_TIME
	local perk = if not isLocal or perkU >= 1 then 0 elseif perkU < 0.15 then perkU / 0.15 else (1 - (perkU - 0.15) / 0.85) ^ 2
	perk = math.min(1, perk + biteK * 0.4)
	local spinAmp = if cheerU >= 0 and cheerU < 1 then math.sin(cheerU * math.pi) * 0.5 else 0
	local spinAngle = cheerU * TAU * 3

	for _, joint in head:GetChildren() do
		if joint:IsA("Motor6D") and (joint.Name == "Antenna1" or joint.Name == "Antenna2") then
			local c0 = base(joint)
			local side = if joint.Name == "Antenna1" then -1 else 1
			local offset = if side < 0 then 0 else 1.3
			local sway = math.sin(now * (if moving then 9 else 2.4) + offset) * (if moving then 0.2 else 0.09) * (1 - 0.6 * heavy)
			-- Giros en los ejes de la cabeza sobre el nacimiento de la antena:
			-- X en + levanta lo que apunta adelante, Y la mece a los lados, Z en -lado la abre hacia fuera
			local lift = perk * 0.35 - heavy * 0.4
			local splay = -side * heavy * 0.3 + side * sway * 0.4
			local spin = if spinAmp > 0
				then CFrame.Angles(0, math.sin(spinAngle + offset) * spinAmp, math.cos(spinAngle + offset) * spinAmp)
				else CFrame.identity
			joint.C0 = CFrame.new(c0.Position) * CFrame.Angles(lift, sway, splay) * spin * c0.Rotation

			-- Codo: Z es su bisagra; en + se dobla más (flagelo hacia abajo), en - se estira hacia arriba
			local scape = joint.Part1
			local elbow = scape and scape:FindFirstChild("AntennaElbow" .. (if side < 0 then 1 else 2))
			if elbow and elbow:IsA("Motor6D") then
				local wave = math.sin(now * (if moving then 9 else 1.7) + offset + 0.8) * (if moving then 0.12 else 0.07)
				local flex = wave - 0.3 * perk + 0.35 * heavy
				elbow.C0 = base(elbow) * CFrame.Angles(0, 0, flex)
			end
		elseif joint:IsA("Weld") then
			local part1 = joint.Part1
			if part1 and part1.Name == "Mandible" and part1:IsA("BasePart") then
				local rest = weldRest(joint)
				if jaw == 0 then
					writeWeld(joint, rest)
				else
					-- Gira sobre la bisagra (cerca del extremo trasero); hacia fuera es -lado.
					-- El gancho va soldado a la mandíbula y la sigue.
					local s = if rest.X < 0 then -1 else 1
					local hinge = (part1.Size.Z - AntModel.JawOverlap * scale) / 2
					writeWeld(joint, rest * CFrame.new(0, 0, hinge) * CFrame.Angles(0, -s * jaw, 0) * CFrame.new(0, 0, -hinge))
				end
			end
		end
	end
end

-- Mordisco de tu hormiga: tirón de cabeza y pinzas que se cierran (≈0,18 s)
function AntAnim.bite()
	biteAt = animClock
end

-- Parada de impacto: tu hormiga se congela `duration` segundos. Con `snap`, si el tirón del
-- mordisco ya pasó su punto fuerte (el servidor tarda en confirmar), la cabeza vuelve de golpe al
-- máximo empuje con las pinzas abiertas, se congela ahí y luego las pinzas se cierran: "¡ÑAC!".
function AntAnim.hitStop(duration: number, snap: boolean?)
	local u = (animClock - biteAt) / BITE_TIME
	if snap and u > 0.3 then
		biteAt = animClock - BITE_TIME * 0.3
	end
	freezeUntil = math.max(freezeUntil, os.clock() + math.clamp(duration, 0, 0.15))
end

-- Saltito con molinillo de antenas, para cuando compras algo
function AntAnim.cheer()
	cheerAt = os.clock()
end

-- Emotes: `fn(dt, t, pose)` toma el control de las uniones de UNA hormiga (t = segundos desde que
-- empezó) y rellena `pose` (ver emotePose). Devuelve false para acabar; nil suelta el control ya.
-- Al acabar, cortarse o reconstruirse la hormiga (LookVersion), la animación normal vuelve a
-- escribir todo desde la pose de reposo, así que no queda ninguna unión torcida.
function AntAnim.override(character: Model, fn: ((number, number, any) -> boolean?)?)
	local st = stateOf(character)
	st.emote = fn
	st.emoteAt = if fn then os.clock() else nil
end

function AntAnim.start()
	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		dt = math.min(dt, 0.1)
		if now >= freezeUntil then
			animClock += dt
		end

		-- Las antenas se levantan un momento cada vez que aparece una comida a tiro
		local target = Targeting.current()
		if target and target ~= lastTarget then
			perkAt = now
		end
		lastTarget = target

		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character then
				animate(player, character, now, dt)
			end
		end
	end)
end

return AntAnim
