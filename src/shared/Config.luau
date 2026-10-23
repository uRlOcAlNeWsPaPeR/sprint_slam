--!strict
-- Central tuning for Sprint Slam. Every gameplay number lives here so balancing never
-- requires touching system code. Units: studs, seconds, studs/second.

local Config = {}

Config.Round = {
	RoundTime = 45,
	CountdownSeconds = 3,
	RestartCountdownSeconds = 2,
	RestartCooldown = 0.6, -- minimum seconds between restart requests
	ResultTimeout = 3, -- client waits this long for the server verdict before showing an error
}

Config.Movement = {
	BaseSpeed = 22, -- speed the instant you start moving
	RunSpeedCap = 58, -- natural top speed from running alone
	OverspeedCap = 100, -- absolute momentum ceiling (boosts, dashes, slopes)
	Acceleration = 30, -- st/s² near BaseSpeed, tapers toward RunSpeedCap
	AccelerationCurve = 0.6, -- higher = stronger taper near the cap
	AirAccelerationScale = 0.25,
	IdleDecay = 70, -- st/s² lost when no input on the ground
	OverspeedDecayGround = 9, -- st/s² lost while above RunSpeedCap on the ground
	OverspeedDecayAir = 3.5,

	-- Carving: max turn rate shrinks as speed rises; turning costs a little momentum.
	TurnRateLow = 16, -- rad/s at BaseSpeed
	TurnRateHigh = 6.5, -- rad/s at RunSpeedCap and above
	AirTurnRateScale = 0.75,
	TurnDrag = 0.1, -- fraction of above-base speed lost per radian turned
	ReverseAngle = 2.0, -- radians; sharper input than this counts as braking
	BrakeDecel = 110,

	-- Collisions: commanded speed collapses toward actual speed when blocked.
	BlockedRatio = 0.55,
	BlockedTime = 0.08,
	BlockedRecover = 6,

	-- Slopes
	DownhillGain = 28, -- st/s² × sin(slope) when running downhill
	UphillLoss = 18,

	-- Jumping & landing
	JumpHeight = 7.5,
	PerfectLandingWindow = 0.2, -- jump or slide this soon after touchdown to keep speed
	PerfectLandingBonus = 3,
	LandingLoss = 0.08, -- fraction of above-base speed lost on a sloppy landing
	LandingMinSpeed = 30, -- landings below this speed are ignored

	-- Sliding
	SlideMinSpeed = 28,
	SlideDuration = 0.9,
	SlideCooldown = 0.45,
	SlideBoost = 6,
	SlideFriction = 5,
	SlideDownhillGain = 70, -- st/s² × sin(slope) while sliding downhill
	SlideTurnRateScale = 0.55,
	SlideTurnDrag = 0.035,
	SlideHipHeightScale = 0.45,
	SlideJumpBoost = 4,

	-- Obstacles
	BonkSpeedScale = 0.55, -- above-base speed kept after hitting a moving obstacle
	BonkKnockback = 34,
	BonkLift = 22,
	BonkCooldown = 0.6,
}

Config.Dash = {
	Cooldown = 1.5,
	Boost = 30, -- temporary speed burst
	Duration = 0.3, -- burst decays to zero over this time
	Retain = 9, -- permanent momentum gain from a dash
	AirLift = 10, -- minimum upward velocity after an air dash
	SteerScale = 0.3, -- turn-rate multiplier while dashing
	BoostChainWindow = 0.4, -- dash within this long after a pad/ring for a chain
	BoostChainBonus = 10,
}

Config.Course = {
	BoostPadSpeed = 20,
	BoostPadRetrigger = 1.0,
	BoostRingSpeed = 16,
	JumpPadRetrigger = 0.8,
}

-- Momentum is your average horizontal speed over the whole run (distance ÷ time since GO).
-- It, not your speed at the lip, sets launch speed, so a late burst only counts for its
-- share of the run and easing off at the end does not buy an easier, slower flight.
Config.Momentum = {
	LaunchScale = 1.8, -- launch speed = momentum × this (clamped to the Slam launch range)
	MeterMax = 85, -- momentum that fills the HUD meter
}

Config.Slam = {
	LaunchPitchDeg = 18,
	MinLaunchSpeed = 70,
	MaxLaunchSpeed = 155,
	FlightGravity = 20,
	SteerAcceleration = 28,
	MaxSteerSpeed = 36, -- cap on lateral speed from steering
	InvertVertical = false,
	SlamDashMinBonus = 0.06, -- speed bonus when slam-dashing right before impact
	SlamDashMaxBonus = 0.15, -- speed bonus when slam-dashing early
	SlamDashFullBonusTime = 1.0, -- seconds before impact that earn the max bonus
	SlamDashSteerScale = 0.35,
	TriggerOffset = 4, -- impact plane sits this far in front of the target face
	MaxFlightTime = 6,
	HitStop = 0.12,
	HitStopExceptional = 0.45,
	ExceptionalScore = 1600, -- slam scores at or above this get the slow-motion treatment
}

-- Zones are checked in order; radius in studs from the target center. Accuracy is a bonus on
-- top of impact power, kept narrow enough that hitting harder always matters most.
Config.Target = {
	Zones = {
		{ Name = "BULLSEYE", Radius = 4.5, Multiplier = 2 },
		{ Name = "INNER", Radius = 11, Multiplier = 1.6 },
		{ Name = "MIDDLE", Radius = 19, Multiplier = 1.3 },
		{ Name = "OUTER", Radius = 30, Multiplier = 1 },
	},
	Wall = { Name = "WALL", Multiplier = 0.5 }, -- hit the wall outside the rings
}

-- Impact Power = ImpactSpeed² ÷ PowerDivisor, where ImpactSpeed is the speed driving into the
-- wall (the normal component). Steering and falling move you along the wall, so they never
-- add power; only momentum and Slam Dash do.
-- Final = round(ImpactPower × ZoneMultiplier) + TimeBonus + ComboBonus
Config.Score = {
	PowerDivisor = 20,
	TimeBonusPerSecond = 10, -- per second remaining at launch
	MaxComboBonus = 600,
	CoinDivisor = 40, -- coins = slam score (power × zone) ÷ this; only verified impacts pay
}

Config.Combo = {
	Window = 3, -- seconds to land the next event and keep the chain
	ChainStep = 0.25, -- multiplier gained per chained event
	MaxMultiplier = 3,
	ServerWindowSlack = 0.35, -- extra window on the server for latency
	-- MinInterval is enforced on the server; Near requires the server-observed position
	-- to have been close to that course element recently.
	Events = {
		BoostPad = { Label = "BOOST", Points = 10, MinInterval = 0.25, Near = "BoostPads" },
		BoostChain = { Label = "BOOST CHAIN", Points = 25, MinInterval = 0.5, Near = "Boosters" },
		BoostRing = { Label = "BOOST RING", Points = 20, MinInterval = 0.5, Near = "BoostRings" },
		PerfectLanding = { Label = "PERFECT LANDING", Points = 15, MinInterval = 0.45 },
		AirDash = { Label = "AIR DASH", Points = 10, MinInterval = 0.5 },
		SlideJump = { Label = "SLIDE JUMP", Points = 10, MinInterval = 0.6 },
		SlamDash = { Label = "SLAM DASH", Points = 20, MinInterval = 5 },
		Shortcut = { Label = "SHORTCUT", Points = 40, MinInterval = 5, ServerOnly = true },
	},
}

Config.Validation = {
	SampleInterval = 0.05,
	SampleBuffer = 120,
	SpeedWindow = 0.5, -- seconds of samples used for plausibility checks
	MaxRunSpeed = 150, -- horizontal; OverspeedCap + dash burst, with slack for jitter
	MaxRiseSpeed = 125, -- upward; jump pads launch at up to ~95
	MaxFlightSpeed = 240,
	SpeedStrikesToInvalidate = 4,
	MaxSampleJump = 45, -- unexplained single-sample jump that counts as a teleport
	FalseStartDistance = 8,
	StartRadius = 20,
	MinRunTime = 9,
	TimeGrace = 0.6,
	ImpactSpeedTolerance = 1.12, -- claimed impact speed may exceed observed by this factor
	MomentumTolerance = 1.06, -- client momentum may exceed the server's by this factor
	MomentumSlack = 3, -- plus this many st/s (sampling and replication delay)
	ImpactPointTolerance = 3.5,
	ImpactWait = 1.0, -- seconds to wait for the other half (claim / server detection)
	ImpactExtrapolate = 30, -- max studs the server will extrapolate to the plane (~2 samples at top speed)
	RespawnTolerance = 25,
	TeleportSettle = 0.3, -- seconds a teleport target must hold before checks resume
	HazardSamplesToInvalidate = 3, -- consecutive samples inside a lethal hazard
	NearDistance = 16,
	NearLookback = 0.8,
}

Config.Hazards = {
	SpinnerSpeedScale = 1.6, -- multiplies every spinner's rad/s in the weekly recipes
}

Config.Camera = {
	BaseFov = 70,
	MaxFov = 96,
	DashFovKick = 8,
	FlightDistance = 20,
	FlightHeight = 6,
}

Config.Effects = {
	TrailMinSpeed = 38,
	StreakMinSpeed = 55,
}

Config.Palette = {
	Charcoal = Color3.fromRGB(18, 20, 26),
	Panel = Color3.fromRGB(26, 29, 37),
	Floor = Color3.fromRGB(52, 58, 74),
	FloorAlt = Color3.fromRGB(64, 71, 90),
	Cyan = Color3.fromRGB(0, 229, 255),
	Orange = Color3.fromRGB(255, 122, 26),
	White = Color3.fromRGB(242, 245, 250),
	Muted = Color3.fromRGB(130, 140, 160),
	Hazard = Color3.fromRGB(235, 238, 245),
	Danger = Color3.fromRGB(255, 40, 80), -- death blocks and lasers
	Blink = Color3.fromRGB(170, 90, 255), -- blink floors
}

-- Fill in audio asset ids to enable sounds; empty ids are skipped silently.
Config.Sounds = {
	Countdown = "",
	Go = "",
	Dash = "",
	Boost = "",
	Land = "",
	Launch = "",
	Impact = "",
	ImpactBig = "",
	Results = "",
}

return Config
