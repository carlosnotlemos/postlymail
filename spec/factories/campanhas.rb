FactoryBot.define do
  factory :campanha do
    empresa
    nome { "Drop Inverno 2026" }
    canal { :email }
    assunto { "Chegou a nova coleção de inverno!" }
    conteudo { "<h1>Nova Coleção</h1><p>Confira os lançamentos no site.</p>" }
    url_midia { nil }
    segmento { :todos }
    status { :rascunho }
    data_envio { nil }
  end
end
