# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Disparos::ProcessarService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'proc-store', ativo: true) }
  let!(:campanha_email) { create(:campanha, empresa: empresa, canal: :email) }
  let!(:campanha_whatsapp) { create(:campanha, empresa: empresa, canal: :whatsapp, assunto: nil) }
  let!(:cliente) { create(:cliente, empresa: empresa, email: 'suporte@loja.com', telefone: '85999998888') }

  describe '.call' do
    context 'quando processando com sucesso' do
      it 'marca como enviado, define timestamp e gera identificador externo para email' do
        disparo = create(:disparo, campanha: campanha_email, cliente: cliente, destinatario: 'contato@cliente.com', status: :na_fila, identificador_externo: nil)

        resultado = described_class.call(disparo: disparo)

        expect(resultado).to be_success
        expect(resultado.data[:enviado]).to be true
        expect(resultado.data[:status]).to eq(:enviado)
        expect(disparo.reload.enviado?).to be true
        expect(disparo.enviado_em).to be_present
        expect(disparo.identificador_externo).to start_with('pst_')
        expect(disparo.mensagem_erro).to be_nil
      end

      it 'permite informar identificador externo customizado' do
        disparo = create(:disparo, campanha: campanha_whatsapp, cliente: cliente, destinatario: '85988887777', status: :na_fila)

        resultado = described_class.call(
          disparo: disparo,
          identificador_externo: 'wpp_msg_12345'
        )

        expect(resultado).to be_success
        expect(disparo.reload.identificador_externo).to eq('wpp_msg_12345')
      end

      it 'resolve o disparo por ID' do
        disparo = create(:disparo, campanha: campanha_email, cliente: cliente, destinatario: 'ok@email.com', status: :na_fila)

        resultado = described_class.call(disparo: disparo.id)

        expect(resultado).to be_success
        expect(disparo.reload.enviado?).to be true
      end
    end

    context 'quando o destinatário é inválido ou simulação de falha' do
      it 'marca como rejeitado quando formato do e-mail for inválido' do
        disparo = create(:disparo, campanha: campanha_email, cliente: cliente, destinatario: 'email_invalido', status: :na_fila)

        resultado = described_class.call(disparo: disparo)

        expect(resultado).to be_success
        expect(resultado.data[:enviado]).to be false
        expect(resultado.data[:status]).to eq(:rejeitado)
        expect(disparo.reload.rejeitado?).to be true
        expect(disparo.mensagem_erro).to include('Endereço de e-mail inválido')
      end

      it 'marca como rejeitado quando telefone whatsapp tiver menos de 8 dígitos' do
        disparo = create(:disparo, campanha: campanha_whatsapp, cliente: cliente, destinatario: '12345', status: :na_fila)

        resultado = described_class.call(disparo: disparo)

        expect(resultado).to be_success
        expect(resultado.data[:enviado]).to be false
        expect(resultado.data[:status]).to eq(:rejeitado)
        expect(disparo.reload.rejeitado?).to be true
        expect(disparo.mensagem_erro).to include('telefone WhatsApp inválido')
      end

      it 'registra falha quando simular_falha for ativado' do
        disparo = create(:disparo, campanha: campanha_email, cliente: cliente, destinatario: 'valido@email.com', status: :na_fila)

        resultado = described_class.call(
          disparo: disparo,
          simular_falha: true,
          motivo_falha: 'SMTP Gateway Timeout'
        )

        expect(resultado).to be_success
        expect(resultado.data[:enviado]).to be false
        expect(disparo.reload.falhou?).to be true
        expect(disparo.mensagem_erro).to eq('SMTP Gateway Timeout')
      end
    end

    context 'validações e casos de erro' do
      it 'falha quando o disparo não existe' do
        resultado = described_class.call(disparo: 999_999)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:disparo_not_found)
      end

      it 'falha quando o disparo já foi enviado e não há forçar: true' do
        disparo = create(:disparo, campanha: campanha_email, cliente: cliente, status: :enviado)

        resultado = described_class.call(disparo: disparo)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:disparo_already_processed)
      end

      it 'falha quando o disparo se encontra cancelado e não há forçar: true' do
        disparo = create(:disparo, campanha: campanha_email, cliente: cliente, status: :cancelado)

        resultado = described_class.call(disparo: disparo)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:disparo_cancelled)
      end

      it 'falha quando a campanha se encontra cancelada e não há forçar: true' do
        campanha_canc = create(:campanha, empresa: empresa, canal: :email, status: :cancelada)
        disparo = create(:disparo, campanha: campanha_canc, cliente: cliente, status: :na_fila)

        resultado = described_class.call(disparo: disparo)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:disparo_cancelled)
      end

      it 'falha quando o disparo se encontra rejeitado e não há forçar: true' do
        disparo = create(:disparo, campanha: campanha_email, cliente: cliente, status: :rejeitado)

        resultado = described_class.call(disparo: disparo)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:disparo_rejected)
      end

      it 'reprocessa disparo já enviado quando forçar for true' do
        disparo = create(:disparo, campanha: campanha_email, cliente: cliente, status: :enviado, destinatario: 'valido@email.com')

        resultado = described_class.call(
          disparo: disparo,
          forcar: true,
          identificador_externo: 'novo_id_99'
        )

        expect(resultado).to be_success
        expect(disparo.reload.identificador_externo).to eq('novo_id_99')
      end
    end

    context 'aliases' do
      it 'funciona através de Disparos::EnviarService e Campanhas::ProcessarDisparoService' do
        d1 = create(:disparo, campanha: campanha_email, cliente: cliente, destinatario: 'a1@email.com', status: :na_fila)
        d2 = create(:disparo, campanha: campanha_email, cliente: cliente, destinatario: 'a2@email.com', status: :na_fila)

        res1 = Disparos::EnviarService.call(disparo: d1)
        res2 = Campanhas::ProcessarDisparoService.call(disparo: d2)

        expect(res1).to be_success
        expect(res2).to be_success
        expect(d1.reload.enviado?).to be true
        expect(d2.reload.enviado?).to be true
      end
    end
  end
end
