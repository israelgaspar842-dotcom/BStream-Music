package com.bstream.bstream_music

import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Provider for the BStream home screen music widget.
 *
 * Phase 1 only: the class exists so the manifest receiver can resolve it.
 * The [HomeWidgetProvider] base class reads the widget data from the
 * SharedPreferences that [HomeWidgetPlugin] writes, exposed through
 * `onUpdate(context, appWidgetManager, appWidgetIds, widgetData)` for the
 * future RemoteViews binding (title, artist, play control).
 */
class MusicWidgetProvider : HomeWidgetProvider()
