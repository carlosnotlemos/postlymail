package br.com.postlymail.controller;

import br.com.postlymail.model.Produto;
import br.com.postlymail.service.ProdutoService;
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
import java.util.List;

public class ProdutosController {

    @FXML private TableView<Produto> tableProdutos;
    @FXML private TableColumn<Produto, String> colNome;
    @FXML private TableColumn<Produto, String> colCategoria;
    @FXML private TableColumn<Produto, BigDecimal> colPreco;
    @FXML private TableColumn<Produto, Integer> colEstoque;
    @FXML private TableColumn<Produto, Void> colAcoes;
    @FXML private ProgressIndicator progressLoading;

    @FXML private Label lblTitulo;
    @FXML private TextField txtNome;
    @FXML private TextField txtCategoria;
    @FXML private TextField txtPreco;
    @FXML private TextField txtEstoque;

    private final ProdutoService produtoService = new ProdutoService();
    private final ObservableList<Produto> observableProdutos = FXCollections.observableArrayList();
    private Produto produtoEmEdicao;

    @FXML
    public void initialize() {
        configurarTabela();
        configurarAcoes();
        carregarProdutos();
    }

    private void configurarTabela() {
        colNome.setCellValueFactory(new PropertyValueFactory<>("nome"));
        colCategoria.setCellValueFactory(new PropertyValueFactory<>("categoria"));
        
        // Formatar preço como moeda
        colPreco.setCellValueFactory(new PropertyValueFactory<>("preco"));
        colPreco.setCellFactory(column -> new TableCell<>() {
            @Override
            protected void updateItem(BigDecimal item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setText(null);
                } else {
                    setText(String.format("R$ %.2f", item));
                }
            }
        });

        colEstoque.setCellValueFactory(new PropertyValueFactory<>("estoque"));
        tableProdutos.setItems(observableProdutos);
    }

    private void configurarAcoes() {
        colAcoes.setCellFactory(column -> new TableCell<>() {
            private final Button btnEdit = new Button("✎");
            private final Button btnDelete = new Button("🗑");
            private final HBox container = new HBox(10, btnEdit, btnDelete);

            {
                btnEdit.getStyleClass().add("button-action-edit");
                btnDelete.getStyleClass().add("button-action-delete");
                btnEdit.setTooltip(new Tooltip("Editar"));
                btnDelete.setTooltip(new Tooltip("Excluir"));

                btnEdit.setOnAction(event -> {
                    Produto produto = getTableView().getItems().get(getIndex());
                    handleEditarProduto(produto);
                });

                btnDelete.setOnAction(event -> {
                    Produto produto = getTableView().getItems().get(getIndex());
                    handleExcluirProduto(produto);
                });
            }

            @Override
            protected void updateItem(Void item, boolean empty) {
                super.updateItem(item, empty);
                if (empty) {
                    setGraphic(null);
                } else {
                    setGraphic(container);
                }
            }
        });
    }

    private void carregarProdutos() {
        Task<List<Produto>> loadTask = new Task<>() {
            @Override
            protected List<Produto> call() {
                return produtoService.listarTodos();
            }
        };

        loadTask.setOnRunning(e -> progressLoading.setVisible(true));
        loadTask.setOnSucceeded(e -> {
            observableProdutos.setAll(loadTask.getValue());
            progressLoading.setVisible(false);
        });
        loadTask.setOnFailed(e -> {
            progressLoading.setVisible(false);
            mostrarAlerta("Erro", "Falha ao carregar produtos: " + loadTask.getException().getMessage());
        });

        new Thread(loadTask).start();
    }

    @FXML
    private void handleNovoProduto(ActionEvent event) {
        produtoEmEdicao = null;
        showProdutoForm(null);
    }

    private void handleEditarProduto(Produto produto) {
        produtoEmEdicao = produto;
        showProdutoForm(produto);
    }

    private void handleExcluirProduto(Produto produto) {
        Alert alert = new Alert(Alert.AlertType.CONFIRMATION);
        alert.setTitle("Confirmar Exclusão");
        alert.setHeaderText("Excluir Produto");
        alert.setContentText("Deseja realmente excluir o produto " + produto.getNome() + "?");
        alert.initStyle(StageStyle.UTILITY);

        alert.showAndWait().ifPresent(response -> {
            if (response == ButtonType.OK) {
                try {
                    produtoService.excluir(produto.getId());
                    carregarProdutos();
                } catch (Exception e) {
                    mostrarAlerta("Erro", "Falha ao excluir produto: " + e.getMessage());
                }
            }
        });
    }

    private void showProdutoForm(Produto produto) {
        try {
            FXMLLoader loader = new FXMLLoader(getClass().getResource("/br/com/postlymail/view/ProdutoFormView.fxml"));
            loader.setController(this);
            Scene scene = new Scene(loader.load());
            
            Stage dialogStage = new Stage();
            dialogStage.initModality(Modality.APPLICATION_MODAL);
            dialogStage.initStyle(StageStyle.UNDECORATED);
            dialogStage.setScene(scene);
            
            if (produto != null) {
                lblTitulo.setText("Editar Produto");
                txtNome.setText(produto.getNome());
                txtCategoria.setText(produto.getCategoria());
                txtPreco.setText(produto.getPreco().toString());
                txtEstoque.setText(produto.getEstoque().toString());
            } else {
                lblTitulo.setText("Novo Produto");
                txtNome.clear();
                txtCategoria.clear();
                txtPreco.clear();
                txtEstoque.clear();
            }

            dialogStage.showAndWait();
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    @FXML
    private void handleSalvar(ActionEvent event) {
        if (txtNome.getText().isEmpty() || txtPreco.getText().isEmpty()) {
            mostrarAlerta("Erro", "Nome e Preço são obrigatórios.");
            return;
        }

        try {
            if (produtoEmEdicao == null) {
                produtoEmEdicao = new Produto();
            }

            produtoEmEdicao.setNome(txtNome.getText());
            produtoEmEdicao.setCategoria(txtCategoria.getText());
            produtoEmEdicao.setPreco(new BigDecimal(txtPreco.getText().replace(",", ".")));
            produtoEmEdicao.setEstoque(Integer.parseInt(txtEstoque.getText()));

            produtoService.salvar(produtoEmEdicao);
            carregarProdutos();
            fecharModal(event);
        } catch (NumberFormatException e) {
            mostrarAlerta("Erro", "Preço ou estoque inválidos.");
        } catch (Exception e) {
            mostrarAlerta("Erro", "Falha ao salvar produto: " + e.getMessage());
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
    }

    private void mostrarAlerta(String titulo, String mensagem) {
        Alert alert = new Alert(Alert.AlertType.ERROR);
        alert.setTitle(titulo);
        alert.setHeaderText(null);
        alert.setContentText(mensagem);
        alert.showAndWait();
    }
}
