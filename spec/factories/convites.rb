FactoryBot.define do
  factory :convite do
    empresa
    association :convidado_por, factory: :usuario
    sequence(:email) { |n| "convidado#{n}@exemplo.com" }
    papel { :atendente }
    expira_em { 7.days.from_now }
    aceito_em { nil }
  end
end
