FactoryBot.define do
  factory :endereco do
    cliente
    titulo { "Casa" }
    cep { "60000000" }
    logradouro { "Rua das Flores" }
    numero { "123" }
    complemento { "Apto 101" }
    bairro { "Centro" }
    cidade { "Fortaleza" }
    estado { "CE" }
    ponto_referencia { "Próximo à praça" }
    padrao { false }
  end
end
