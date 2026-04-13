package br.com.postlymail.controller;

import javafx.event.ActionEvent;
import javafx.fxml.FXML;
import javafx.fxml.FXMLLoader;
import javafx.scene.Node;
import javafx.scene.control.Button;
import javafx.scene.layout.StackPane;
import java.io.IOException;

public class MainController {

    @FXML
    private StackPane contentArea;

    @FXML
    private Button btnDashboard, btnClientes, btnProdutos, btnVendas;

    private Button currentActiveButton;

    @FXML
    public void initialize() {
        currentActiveButton = btnDashboard;
        loadView("DashboardView.fxml");
    }

    @FXML
    private void handleNavigation(ActionEvent event) {
        Button clickedButton = (Button) event.getSource();
        
        if (clickedButton == currentActiveButton) return;

        // Update UI
        currentActiveButton.getStyleClass().remove("nav-button-active");
        clickedButton.getStyleClass().add("nav-button-active");
        currentActiveButton = clickedButton;

        // Load View
        String viewName = "";
        if (clickedButton == btnDashboard) viewName = "DashboardView.fxml";
        else if (clickedButton == btnClientes) viewName = "ClientesView.fxml";
        else if (clickedButton == btnProdutos) viewName = "ProdutosView.fxml";
        else if (clickedButton == btnVendas) viewName = "VendasView.fxml";

        loadView(viewName);
    }

    private void loadView(String fxmlFile) {
        try {
            FXMLLoader loader = new FXMLLoader(getClass().getResource("/br/com/postlymail/view/" + fxmlFile));
            Node view = loader.load();
            contentArea.getChildren().setAll(view);
        } catch (IOException e) {
            System.err.println("Erro ao carregar view: " + fxmlFile);
            e.printStackTrace();
        }
    }
}
