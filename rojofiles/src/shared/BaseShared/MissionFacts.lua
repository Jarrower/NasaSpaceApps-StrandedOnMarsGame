--[[
	MissionFacts  (ModuleScript)
	Location: ReplicatedStorage > BaseShared > MissionFacts

	"Did you know?" cards for Mars Base 7. Every fact was checked against a
	NASA source (Url). The full list with sources for the judges is in docs/NASA_SOURCES.md.

	Tag decides when a card is shown:
	  "DustStorm" / "SolarStorm" / "Micrometeorite"  after a sol with that event
	  "Oxygen" / "Food" / "Health" / "Fuel"          on the failure screen for that meter
	  "General"                                      on calm sols, in order
	A fact can have several tags.
]]

local Facts = {
	{
		Id = "Sol", Tags = { "General" },
		Title = "A day on Mars",
		Text = "A day on Mars is called a sol. It lasts about 24 hours and 39 minutes, a little longer than a day on Earth.",
		Source = "NASA Goddard Institute for Space Studies, Mars24 notes",
		Url = "https://www.giss.nasa.gov/tools/mars24/",
	},
	{
		Id = "Gravity", Tags = { "General" },
		Title = "Feeling light",
		Text = "Gravity on Mars is only 38% as strong as on Earth. A backpack that weighs 10 kg on Earth would feel like less than 4 kg on Mars.",
		Source = "NASA JPL, Mars at a Glance",
		Url = "https://www.jpl.nasa.gov/news/press_kits/insight/launch/facts/mars-at-a-glance",
	},
	{
		Id = "Veggie", Tags = { "General", "Food" },
		Title = "Space salad",
		Text = "Astronauts can grow food in space! In 2015, astronauts on the Space Station ate red romaine lettuce they grew in NASA's Veggie plant system.",
		Source = "NASA Technical Reports Server, Veggie",
		Url = "https://ntrs.nasa.gov/citations/20160004060",
	},
	{
		Id = "Moxie", Tags = { "General", "Oxygen" },
		Title = "Making air on Mars",
		Text = "Mars air is mostly carbon dioxide. NASA's MOXIE, on the Perseverance rover, pulled oxygen out of it: 122 grams in total, about what a small dog breathes in 10 hours.",
		Source = "NASA JPL, MOXIE Completes Mars Mission (2023)",
		Url = "https://www.jpl.nasa.gov/news/nasas-oxygen-generating-experiment-moxie-completes-mars-mission/",
	},
	{
		Id = "MagneticField", Tags = { "General", "Health", "SolarStorm" },
		Title = "No magnetic shield",
		Text = "Earth's magnetic field protects us from the Sun's particles. Mars lost its global magnetic field long ago, so more radiation reaches the ground.",
		Source = "NASA, Mars Facts",
		Url = "https://science.nasa.gov/mars/facts/",
	},
	{
		Id = "Shelter", Tags = { "General", "Health" },
		Title = "Hiding from radiation",
		Text = "Scientists use radiation measurements from the Curiosity rover to plan how astronauts will stay safe. Astronauts could even use the Martian landscape as a shield.",
		Source = "NASA, NASA Watches Mars Light Up During Epic Solar Storm (2024)",
		Url = "https://www.nasa.gov/solar-system/planets/mars/nasa-watches-mars-light-up-during-epic-solar-storm/",
	},
	{
		Id = "MoxieFuel", Tags = { "General", "Fuel" },
		Title = "Fuel for the trip home",
		Text = "Rockets need oxygen to burn their fuel. MOXIE tested a way to make that oxygen on Mars, so a future rocket could carry astronauts back to Earth.",
		Source = "NASA, MOXIE Completes Mars Mission (2023)",
		Url = "https://www.nasa.gov/missions/mars-2020-perseverance/nasas-oxygen-generating-experiment-moxie-completes-mars-mission/",
	},
	{
		Id = "Opportunity", Tags = { "DustStorm" },
		Title = "The storm that stopped a rover",
		Text = "In 2018 a dust storm covered all of Mars and blocked the Sun. The solar-powered rover Opportunity could not recharge. It was planned to last 90 days, but it explored for almost 15 years!",
		Source = "NASA JPL, Opportunity Rover Mission Comes to End (2019)",
		Url = "https://www.jpl.nasa.gov/news/nasas-opportunity-rover-mission-on-mars-comes-to-end/",
	},
	{
		Id = "InSightDust", Tags = { "DustStorm" },
		Title = "Dusty solar panels",
		Text = "When a dust storm blew over NASA's InSight lander in 2022, less sunlight reached its solar panels. Its power dropped by about one third.",
		Source = "NASA, NASA's InSight Waits Out Dust Storm (2022)",
		Url = "https://www.nasa.gov/missions/insight/nasas-insight-waits-out-dust-storm/",
	},
	{
		Id = "RadStorm", Tags = { "SolarStorm", "Health" },
		Title = "A real solar storm",
		Text = "Curiosity's RAD instrument measures radiation on Mars. In May 2024 a huge solar storm hit. An astronaut next to Curiosity would have received about as much radiation as 30 chest X-rays.",
		Source = "NASA, NASA Watches Mars Light Up During Epic Solar Storm (2024)",
		Url = "https://www.nasa.gov/solar-system/planets/mars/nasa-watches-mars-light-up-during-epic-solar-storm/",
	},
	{
		Id = "Meteoroid", Tags = { "Micrometeorite" },
		Title = "Space rocks",
		Text = "Mars air is only about 1% as thick as Earth's, so space rocks that would burn up in our sky can reach the ground. In 2021 NASA's InSight lander felt one hit Mars.",
		Source = "NASA, InSight Lander Detects Stunning Meteoroid Impact on Mars (2022)",
		Url = "https://www.nasa.gov/missions/insight/nasas-insight-lander-detects-stunning-meteoroid-impact-on-mars/",
	},
}

local MissionFacts = { List = Facts }

local function hasTag(f, tag)
	return table.find(f.Tags, tag) ~= nil
end

-- Pick the first fact with this tag that is not in `used` (a set of Ids).
-- Falls back to any unused General fact, then to the first fact with the tag.
function MissionFacts.Pick(tag, used)
	used = used or {}
	for _, f in ipairs(Facts) do
		if hasTag(f, tag) and not used[f.Id] then
			return f
		end
	end
	for _, f in ipairs(Facts) do
		if hasTag(f, "General") and not used[f.Id] then
			return f
		end
	end
	for _, f in ipairs(Facts) do
		if hasTag(f, tag) then
			return f
		end
	end
	return Facts[1]
end

function MissionFacts.Get(index)
	return Facts[math.clamp(math.floor(tonumber(index) or 1), 1, #Facts)]
end

return MissionFacts
