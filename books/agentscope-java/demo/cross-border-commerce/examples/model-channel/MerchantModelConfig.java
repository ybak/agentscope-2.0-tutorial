package io.agentscope.builder.web.config;

import io.agentscope.core.model.ModelRegistry;
import io.agentscope.extensions.model.openai.OpenAIChatModel;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** 教学适配：复制到 Dataplane 扫描包，并在其 POM 加入 OpenAI 模型扩展。 */
@Configuration(proxyBeanMethods = false)
@ConditionalOnProperty(name = "merchant.model.enabled", havingValue = "true")
public class MerchantModelConfig {
    @Bean
    InitializingBean registerMerchantGatewayModel(
            @Value("${merchant.model.base-url}") String baseUrl,
            @Value("${merchant.model.endpoint-path:/v1/chat/completions}") String endpointPath,
            @Value("${merchant.model.api-key}") String apiKey,
            @Value("${merchant.model.name}") String modelName) {
        return () -> {
            if (baseUrl.isBlank() || apiKey.isBlank() || modelName.isBlank()) {
                throw new IllegalArgumentException("merchant.model URL, key and name are required");
            }
            // 平台别名与上游模型名分开；不替换其他 Agent 的默认 Model bean。
            ModelRegistry.register("merchant-gateway", OpenAIChatModel.builder()
                    .baseUrl(baseUrl)
                    .endpointPath(endpointPath)
                    .apiKey(apiKey)
                    .modelName(modelName)
                    .stream(true)
                    .build());
        };
    }
}
