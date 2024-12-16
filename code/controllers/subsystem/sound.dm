SUBSYSTEM_DEF(sound)
	name = "Sound"
	flags = SS_POST_FIRE_TIMING|SS_NO_INIT
	wait = 2
	priority = SS_PRIORITY_SOUND
	runlevels = RUNLEVELS_DEFAULT|RUNLEVEL_LOBBY

	/// Assoc list of the full template queue and their list of hearers, in the form of: template = hearers
	var/list/template_queue = list()
	/// Assoc list of templates being processed during this tick and their list of hearers, in the form of: template = hearers
	var/list/run_queue = list()
	/// Hearers for current template being processed
	var/list/run_hearers = null
	/// Assoc list of tracked channels currently playing and their template, in the form of: "[channel]" = template
	var/list/channel_templates = list()
	/// List of clients who have moved and need all their sounds updated.
	var/list/hearer_updates = list()
	/// List of templates whose source has moved and need to update their hearers.
	var/list/source_updates = list()

/datum/controller/subsystem/sound/fire(resumed = FALSE)
	if(!resumed) // Controller first firing for this tick
		run_queue = template_queue.Copy()
		template_queue = list()
		run_hearers = null // null explicitely indicates we need to do ranging!

	for(var/datum/sound_template/run_template in run_queue)
		if(!run_hearers) // Initialize for handling next template
			run_hearers = run_queue[run_template] // get initial hearers
			channel_templates["[run_template.channel]"] = run_template
			run_template.hearers = run_hearers.Copy()
			if(MC_TICK_CHECK)
				return

		while(length(run_hearers)) // Output sound to hearers
			var/client/hearer = run_hearers[length(run_hearers)]
			run_hearers.len--
			hearer?.soundOutput.process_template(run_template)
			if(MC_TICK_CHECK)
				return

		run_template.on_playing()

		run_queue.Remove(run_template) // Everyone that had to get this sound got it. Bye, template
		run_hearers = null // Reset so we know next one is new

	var/list/updated_clients = list()

	list_clear_nulls(hearer_updates)
	for(var/client/client as anything in hearer_updates)
		client.soundOutput.update_tracked_channels()
		updated_clients += client
		hearer_updates -= client
		if(MC_TICK_CHECK)
			return

	for(var/datum/sound_template/template as anything in source_updates)
		list_clear_nulls(template.hearers)
		for(var/client/client as anything in (template.hearers - updated_clients))
			client.soundOutput.process_template(template, update = TRUE)
		source_updates -= template
		if(MC_TICK_CHECK)
			return

/datum/controller/subsystem/sound/proc/queue(datum/sound_template/template, list/hearers)
	LAZYINITLIST(hearers)

	if(!(template.sound_flags & SOUND_TEMPLATE_SPATIAL))
		template_queue[template] = hearers
		return

	var/turf/source_turf = get_turf(template.source)
	if(SSinterior.in_interior(source_turf)) //from interior, get hearers in interior and nearby to exterior
		var/datum/interior/interior = SSinterior.get_interior_by_coords(source_turf.x, source_turf.y, source_turf.z)
		var/list/bounds = interior.get_middle_coords()
		hearers |= SSquadtree.players_in_range(RECT(bounds[1], bounds[2], interior.map_template.width, interior.map_template.height), bounds[3]) //in interior
		if(interior.exterior)
			hearers |= SSquadtree.players_in_range(SQUARE(interior.exterior.x, interior.exterior.y, template.range * 2), interior.exterior.z) //nearby to exterior

	else //from exterior, get hearers nearby and in nearby interiors
		hearers |= SSquadtree.players_in_range(SQUARE(source_turf.x, source_turf.y, template.range * 2), source_turf.z) //nearby
		for(var/datum/interior/interior in SSinterior.interiors)
			if(!interior.ready)
				continue
			if(interior.exterior?.z != source_turf.z)
				continue
			if(get_dist(interior.exterior, source_turf) > template.range)
				continue
			var/list/bounds = interior.get_middle_coords()
			hearers |= SSquadtree.players_in_range(RECT(bounds[1], bounds[2], interior.map_template.width, interior.map_template.height), bounds[3]) //nearby interiors

	template_queue[template] = hearers
