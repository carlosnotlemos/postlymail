FactoryBot.define do
  factory :membro do
    empresa
    usuario
    convidado_por { nil }
    papel { :atendente }
    ativo { true }
    data_entrada { Time.current }
  end
end
