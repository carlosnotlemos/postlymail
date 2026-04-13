package br.com.postlymail.controller;

import br.com.postlymail.model.Cliente;
import br.com.postlymail.model.ItemVenda;
import br.com.postlymail.model.Produto;
import br.com.postlymail.model.Venda;
import br.com.postlymail.service.ClienteService;
import br.com.postlymail.service.ProdutoService;
import br.com.postlymail.service.VendaService;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import javafx.concurrent.Task;
import javafx.event.ActionEvent;
import javafx.fxml.FXML;
import javafx.fxml.FXMLLoader;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.control.cell.PropertyValueFactory;
import javafx.scene.layout.HBox;
import javafx.stage.Modality;
import javafx.stage.Stage;
import javafx.stage.StageStyle;
import java.io.IOException;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

public class VendasController {

    @FXML private TableView<Venda> tableVendas;
    @FXML private TableColumn<Venda, LocalDateTime> colData;
    @FXML private TableColumn<Venda, String> colCliente;
    @FXML private TableColumn<Venda, BigDecimal> colValor;
    @FXML private TableColumn<Venda, Void> colAcoes;
    @FXML private ProgressIndicator progressLoading;

    // Campos do Formulário
    @FXML private ComboBox<Cliente> cbCliente;
    @FXML private ComboBox<Produto> cbProduto;
    @FXML private TextField txtQuantidade;
    @FXML private TableView<ItemVenda> tableItems;
    @FXML private TableColumn<ItemVenda, String> colItemProduto;
    @FXML private TableColumn<ItemVenda, BigDecimal> colItemPreco;
    @FXML private TableColumn<ItemVenda, Integer> colItemQtd;
    @FXML private TableColumn<ItemVenda, BigDecimal> colItemTotal;
    @FXML private TableColumn<ItemVenda, Void> colItemAcoes;
    @FXML private Label lblTotalVenda;

    private final VendaService vendaService = new VendaService();
    private final ClienteService clienteService = new ClienteService();
    private final ProdutoService produtoService = new ProdutoService();
    
    private final ObservableList<Venda> observableVendas = FXCollections.observableArrayList();
    private final ObservableList<ItemVenda> observableItems = FXCollections.observableArrayList();
    
    private Venda vendaAtual;

    @FXML
    public void initialize() {
        if (tableVendas != null) {
            configurarTabelaPrincipal();
            configurarAcoes();
            carregarVendas();
        }
        
        if (tableItems != null) {
            configurarTabelaItems();
            configurarAcoesItems();
            configurarCombos();
            if (vendaAtual == null) {
                vendaAtual = new Venda();
            }
        }
    }

    private void configurarTabelaPrincipal() {
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm");
        colData.setCellValueFactory(new PropertyValueFactory<>("dataVenda"));
        colData.setCellFactory(column -> new TableCell<>() {
            @Override
            protected void updateItem(LocalDateTime item, boolean empty) {
                super.updateItem(item, empty);
                setText(empty || item == null ? null : item.format(formatter));
            }
        });

        colCliente.setCellValueFactory(cellData -> 
            new javafx.beans.property.SimpleStringProperty(cellData.getValue().getCliente().getNome()));
        
        colValor.setCellValueFactory(new PropertyValueFactory<>("valorTotal"));
        colValor.setCellFactory(column -> new TableCell<>() {
            @Override
            protected void updateItem(BigDecimal item, boolean empty) {
                super.updateItem(item, empty);
                setText(empty || item == null ? null : String.format("R$ %.2f", item));
            }
        });

        tableVendas.setItems(observableVendas);
    }

    private void configurarAcoes() {
        colAcoes.setCellFactory(column -> new TableCell<>() {
            private final Button btnEdit = new Button("✎");
            private final Button btnDelete = new Button("🗑");
            private final HBox container = new HBox(10, btnEdit, btnDelete);
            {
                btnEdit.getStyleClass().add("button-action-edit");
                btnDelete.getStyleClass().add("button-action-delete");
                btnEdit.setTooltip(new Tooltip("Editar Venda"));
                btnDelete.setTooltip(new Tooltip("Excluir Venda"));

                btnEdit.setOnAction(event -> {
                    Venda venda = getTableView().getItems().get(getIndex());
                    handleEditarVenda(venda);
                });

                btnDelete.setOnAction(event -> {
                    Venda venda = getTableView().getItems().get(getIndex());
                    handleExcluirVenda(venda);
                });
            }

            @Override
            protected void updateItem(Void item, boolean empty) {
                super.updateItem(item, empty);
                setGraphic(empty ? null : container);
            }
        });
    }

    private void handleEditarVenda(Venda venda) {
        vendaAtual = venda;
        showVendaForm();
    }

    private void handleExcluirVenda(Venda venda) {
        Alert alert = new Alert(Alert.AlertType.CONFIRMATION);
        alert.setTitle("Confirmar Estorno");
        alert.setHeaderText("Excluir Venda");
        alert.setContentText("Deseja estornar esta venda? Os itens retornarão ao estoque.");
        alert.initStyle(StageStyle.UTILITY);

        alert.showAndWait().ifPresent(response -> {
            if (response == ButtonType.OK) {
                try {
                    vendaService.excluir(venda.getId());
                    carregarVendas();
                } catch (Exception e) {
                    mostrarAlerta("Erro", "Falha ao excluir venda: " + e.getMessage());
                }
            }
        });
    }

    private void configurarTabelaItems() {
        colItemProduto.setCellValueFactory(cellData -> 
            new javafx.beans.property.SimpleStringProperty(cellData.getValue().getProduto().getNome()));
        
        colItemPreco.setCellValueFactory(new PropertyValueFactory<>("precoUnitario"));
        colItemPreco.setCellFactory(column -> new TableCell<>() {
            @Override
            protected void updateItem(BigDecimal item, boolean empty) {
                super.updateItem(item, empty);
                setText(empty || item == null ? null : String.format("R$ %.2f", item));
            }
        });

        colItemQtd.setCellValueFactory(new PropertyValueFactory<>("quantidade"));
        
        colItemTotal.setCellValueFactory(cellData -> {
            ItemVenda item = cellData.getValue();
            return new javafx.beans.property.SimpleObjectProperty<>(
                item.getPrecoUnitario().multiply(new BigDecimal(item.getQuantidade()))
            );
        });
        colItemTotal.setCellFactory(column -> new TableCell<>() {
            @Override
            protected void updateItem(BigDecimal item, boolean empty) {
                super.updateItem(item, empty);
                setText(empty || item == null ? null : String.format("R$ %.2f", item));
            }
        });

        tableItems.setItems(observableItems);
    }

    private void configurarAcoesItems() {
        colItemAcoes.setCellFactory(column -> new TableCell<>() {
            private final Button btnRemove = new Button("×");
            {
                btnRemove.setStyle("-fx-background-color: transparent; -fx-text-fill: #f38ba8; -fx-font-weight: bold; -fx-cursor: hand;");
                btnRemove.setOnAction(event -> {
                    ItemVenda item = getTableView().getItems().get(getIndex());
                    vendaAtual.getItens().remove(item);
                    observableItems.remove(item);
                    atualizarTotal();
                });
            }

            @Override
            protected void updateItem(Void item, boolean empty) {
                super.updateItem(item, empty);
                setGraphic(empty ? null : btnRemove);
            }
        });
    }

    private void configurarCombos() {
        // Carregamento assíncrono para os combos também seria ideal, mas usaremos direto por simplicidade inicial
        cbCliente.setItems(FXCollections.observableArrayList(clienteService.listarTodos()));
        cbProduto.setItems(FXCollections.observableArrayList(produtoService.listarTodos()));
    }

    private void carregarVendas() {
        Task<List<Venda>> loadTask = new Task<>() {
            @Override
            protected List<Venda> call() {
                return vendaService.listarTodas();
            }
        };

        loadTask.setOnRunning(e -> progressLoading.setVisible(true));
        loadTask.setOnSucceeded(e -> {
            observableVendas.setAll(loadTask.getValue());
            progressLoading.setVisible(false);
        });
        loadTask.setOnFailed(e -> {
            progressLoading.setVisible(false);
            e.getSource().getException().printStackTrace();
        });

        new Thread(loadTask).start();
    }

    @FXML
    private void handleNovaVenda(ActionEvent event) {
        vendaAtual = new Venda();
        showVendaForm();
    }

    private void showVendaForm() {
        try {
            FXMLLoader loader = new FXMLLoader(getClass().getResource("/br/com/postlymail/view/VendaFormView.fxml"));
            loader.setController(this);
            Scene scene = new Scene(loader.load());
            
            // Link css
            scene.getStylesheets().add(getClass().getResource("/br/com/postlymail/css/style.css").toExternalForm());

            Stage dialogStage = new Stage();
            dialogStage.initModality(Modality.APPLICATION_MODAL);
            dialogStage.initStyle(StageStyle.UNDECORATED);
            dialogStage.setScene(scene);
            
            if (vendaAtual.getId() != null) {
                cbCliente.setValue(vendaAtual.getCliente());
                observableItems.setAll(vendaAtual.getItens());
                atualizarTotal();
            } else {
                observableItems.clear();
                atualizarTotal();
            }

            dialogStage.showAndWait();
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    @FXML
    private void handleAdicionarItem(ActionEvent event) {
        Produto produto = cbProduto.getValue();
        String qtdStr = txtQuantidade.getText();

        if (produto == null || qtdStr.isEmpty()) {
            return;
        }

        try {
            int qtd = Integer.parseInt(qtdStr);
            if (qtd <= 0) throw new NumberFormatException();
            
            if (produto.getEstoque() != null && qtd > produto.getEstoque()) {
                mostrarAlerta("Estoque Insuficiente", "O produto " + produto.getNome() + " possui apenas " + produto.getEstoque() + " unidades.");
                return;
            }

            ItemVenda item = new ItemVenda(produto, qtd);
            vendaAtual.adicionarItem(item);
            observableItems.add(item);
            
            atualizarTotal();
            
            // Limpar seleção
            cbProduto.setValue(null);
            txtQuantidade.setText("1");
        } catch (NumberFormatException e) {
            mostrarAlerta("Erro", "Quantidade inválida.");
        }
    }

    private void atualizarTotal() {
        lblTotalVenda.setText(String.format("R$ %.2f", vendaAtual.getValorTotal()));
    }

    @FXML
    private void handleFinalizarVenda(ActionEvent event) {
        Cliente cliente = cbCliente.getValue();
        if (cliente == null) {
            mostrarAlerta("Erro", "Selecione um cliente.");
            return;
        }

        if (vendaAtual.getItens().isEmpty()) {
            mostrarAlerta("Erro", "Adicione ao menos um produto.");
            return;
        }

        vendaAtual.setCliente(cliente);
        try {
            vendaService.salvarVenda(vendaAtual);
            fecharModal(event);
            carregarVendas();
        } catch (Exception e) {
            mostrarAlerta("Erro", "Erro ao salvar venda: " + e.getMessage());
        }
    }

    @FXML
    private void handleCancelar(ActionEvent event) {
        fecharModal(event);
    }

    private void fecharModal(ActionEvent event) {
        Button btn = (Button) event.getSource();
        Stage stage = (Stage) btn.getScene().getWindow();
        stage.close();
        
        // Reset
        vendaAtual = new Venda();
        observableItems.clear();
    }

    private void mostrarAlerta(String titulo, String mensagem) {
        Alert alert = new Alert(Alert.AlertType.WARNING);
        alert.setTitle(titulo);
        alert.setHeaderText(null);
        alert.setContentText(mensagem);
        alert.showAndWait();
    }
}
