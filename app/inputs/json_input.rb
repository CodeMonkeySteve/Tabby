# class JsonInput < SimpleForm::Inputs::StringInput
#   def input(wrapper_options)
#     input_html_options[:type] ||= input_type
#
#     val = object.public_send(attribute_name).to_json if object.public_send(attribute_name).present?
#     @builder.text_area(attribute_name, input_html_options.deep_merge(value: val))
#   end
# end
