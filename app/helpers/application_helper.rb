module ApplicationHelper
  def nav_link(path, name = nil, &name_block)
    name ||= capture(&name_block)
    a_opts = { class: ['nav-link'], 'data-turbo-frame': '_top'}
    current_page?(path) and a_opts[:class] << 'active'
    content_tag :li, link_to(name, path, a_opts), class: 'nav-item'
  end
end
