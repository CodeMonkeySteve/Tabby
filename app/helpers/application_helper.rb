module ApplicationHelper
  def nav_link(path, name = nil, &name_block)
    name ||= capture(&name_block)
    a_opts = { class: ['nav-link'], 'data-turbo-frame': '_top'}
    current_page?(path) and a_opts[:class] << 'active'
    content_tag :li, link_to(name, path, a_opts), class: 'nav-item'
  end

  # e.g. "1h 5m", "12m", or "45s"
  def practice_time(seconds)
    hours, minutes = (seconds.to_i / 60).divmod(60)
    if hours.positive? then "#{hours}h #{minutes}m"
    elsif minutes.positive? then "#{minutes}m"
    else "#{seconds.to_i}s"
    end
  end

  # Attributes of a song's playlist menu icon, highlighted if it's in a playlist
  def playlist_icon_attributes(song, playlists)
    { class: playlists.any? { it.song_ids.include?(song.id) } ? 'playlist-icon in-playlist' : 'playlist-icon',
      data: { song: song.id } }
  end

  # e.g. "Today", "Yesterday", "3 days ago", or "Jun 4" for dates over a week ago
  def relative_date(date, today: Date.current)
    case (today - date).to_i
      when 0 then "Today"
      when 1 then "Yesterday"
      when 2..6 then "#{(today - date).to_i} days ago"
      else date.strftime('%b %-d')
    end
  end
end
