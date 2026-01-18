class ArrayInput < SimpleForm::Inputs::StringInput
  def input(wrapper_options)
    input_html_options[:type] ||= input_type

    # Generate a text field for each existing array element
    Array(object.public_send(attribute_name)).map do |array_el|
      @builder.text_field(nil, input_html_options.merge(value: array_el, name: "#{object_name}[#{attribute_name}][]"))
    end.join.html_safe

    # Note: For new records or empty arrays, the initial field will need to be added manually or via Stimulus on connect.
  end

  def input_type
    :text
  end
end
